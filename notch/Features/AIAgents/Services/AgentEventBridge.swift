import Foundation
import Darwin

/// Nonblocking, same-user Unix socket. One bounded JSON line per connection.
/// No TCP listener, credentials, transcripts, disk queue, or executable payloads.
@MainActor
final class AgentEventBridge {
    struct BridgeError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private struct Client {
        let source: DispatchSourceRead
        let deadline: Date
        var buffer = Data()
    }
    let directory: URL
    var socketPath: String { directory.appendingPathComponent("events.sock").path }
    var onEvent: ((Data) -> Void)?
    var onRejectedMessage: (() -> Void)?
    private var listener: DispatchSourceRead?
    private var lockFD: Int32 = -1
    private var clients: [Int32: Client] = [:]
    private var rateWindow = Date.distantPast
    private var accepted = 0
    private var listenerPaused = false

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notch")) {
        self.directory = directory
    }

    func start() throws {
        guard listener == nil else { return }
        guard socketPath.utf8.count < 104 else { throw BridgeError("Home directory path is too long for the local socket.") }
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw BridgeError("The ~/.notch directory must be owned by you, not a symlink, and have permissions 700.")
        }
        lockFD = Darwin.open(directory.appendingPathComponent("bridge.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { throw BridgeError("Cannot open the local bridge lock.") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFD)
            lockFD = -1
            throw BridgeError("Another notch instance is already receiving agent events.")
        }
        do {
            if lstat(socketPath, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else {
                    throw BridgeError("Refusing to replace an unexpected file at the local socket path.")
                }
                guard unlink(socketPath) == 0 else { throw BridgeError("Cannot remove the stale local socket.") }
            }
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw BridgeError("Cannot create the local socket.") }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            withUnsafeMutableBytes(of: &address.sun_path) { bytes in
                bytes.copyBytes(from: Array(socketPath.utf8) + [0])
            }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, chmod(socketPath, 0o600) == 0,
                  fcntl(fd, F_SETFL, O_NONBLOCK) == 0, listen(fd, 8) == 0 else {
                Darwin.close(fd)
                throw BridgeError("Cannot bind the local agent socket.")
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.acceptClients(fd) }
            }
            source.setCancelHandler { Darwin.close(fd) }
            listener = source
            rateWindow = Date()
            accepted = 0
            source.resume()
        } catch {
            Darwin.close(lockFD)
            lockFD = -1
            throw error
        }
    }

    func stop() {
        let wasListening = listener != nil
        if listenerPaused { listener?.resume(); listenerPaused = false }
        listener?.cancel()
        listener = nil
        for fd in Array(clients.keys) { closeClient(fd) }
        if wasListening { unlink(socketPath) }
        if lockFD >= 0 {
            flock(lockFD, LOCK_UN)
            Darwin.close(lockFD)
            lockFD = -1
        }
    }

    func maintain(now: Date) {
        for (fd, client) in clients where now >= client.deadline { closeClient(fd) }
        if listenerPaused && now.timeIntervalSince(rateWindow) >= 1 {
            rateWindow = now
            accepted = 0
            listenerPaused = false
            listener?.resume()
        }
    }

    private func acceptClients(_ listenerFD: Int32) {
        let now = Date()
        if now.timeIntervalSince(rateWindow) >= 1 {
            rateWindow = now
            accepted = 0
        }
        // Bound work per callback, open clients, and total accepted messages per second.
        for _ in 0..<16 {
            if accepted >= 60 {
                listenerPaused = true
                listener?.suspend()
                break
            }
            let fd = accept(listenerFD, nil, nil)
            guard fd >= 0 else { break }
            accepted += 1
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard clients.count < 8, getpeereid(fd, &uid, &gid) == 0,
                  uid == getuid(), fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                Darwin.close(fd)
                continue
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.readClient(fd) }
            }
            source.setCancelHandler { Darwin.close(fd) }
            clients[fd] = Client(source: source, deadline: now.addingTimeInterval(2))
            source.resume()
        }
    }

    private func readClient(_ fd: Int32) {
        guard var client = clients[fd] else { return }
        var bytes = [UInt8](repeating: 0, count: AgentBridgeEvent.maximumBytes + 1)
        let count = Darwin.read(fd, &bytes, bytes.count)
        if count < 0 && (errno == EAGAIN || errno == EINTR) { return }
        guard count > 0 else {
            if !client.buffer.isEmpty { onRejectedMessage?() }
            closeClient(fd)
            return
        }
        client.buffer.append(contentsOf: bytes.prefix(count))
        guard client.buffer.count <= AgentBridgeEvent.maximumBytes else {
            onRejectedMessage?()
            closeClient(fd)
            return
        }
        if let newline = client.buffer.firstIndex(of: 10) {
            let payload = Data(client.buffer[..<newline])
            closeClient(fd)
            onEvent?(payload)
        } else {
            clients[fd] = client
        }
    }

    private func closeClient(_ fd: Int32) {
        clients.removeValue(forKey: fd)?.source.cancel()
    }
}
