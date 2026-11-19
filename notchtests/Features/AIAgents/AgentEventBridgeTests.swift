import Darwin
import XCTest
@testable import notch

@MainActor
final class AgentEventBridgeTests: XCTestCase {
    private func directory() -> URL {
        // Unix sockets have a 104-byte path limit; macOS's default temp path is long.
        FileManager.default.temporaryDirectory.appendingPathComponent("dn-\(UUID().uuidString.prefix(6))")
    }

    private func connect(to bridge: AgentEventBridge) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: Array(bridge.socketPath.utf8) + [0])
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw POSIXError(.ECONNREFUSED)
        }
        return fd
    }

    func testRealSocketReceivesFragmentedJSONAndCleansUp() async throws {
        let directory = directory()
        let bridge = AgentEventBridge(directory: directory)
        defer { bridge.stop(); try? FileManager.default.removeItem(at: directory) }
        try bridge.start()
        let received = expectation(description: "received")
        bridge.onEvent = { data in
            XCTAssertEqual(String(data: data, encoding: .utf8), "{\"version\":1}")
            received.fulfill()
        }
        let fd = try connect(to: bridge)
        defer { Darwin.close(fd) }
        let first = Array("{\"version\":".utf8)
        let second = Array("1}\n".utf8)
        XCTAssertEqual(Darwin.write(fd, first, first.count), first.count)
        await Task.yield()
        XCTAssertEqual(Darwin.write(fd, second, second.count), second.count)
        await fulfillment(of: [received], timeout: 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: bridge.socketPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        bridge.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.socketPath))
    }

    func testSecondInstanceCannotStealSocketAndStopIsIdempotent() throws {
        let directory = directory()
        let first = AgentEventBridge(directory: directory)
        let second = AgentEventBridge(directory: directory)
        defer {
            second.stop(); first.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        try first.start()
        XCTAssertThrowsError(try second.start())
        second.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.socketPath))
        first.stop()
        first.stop()
        try second.start()
    }

    func testRefusesUnsafeDirectoryAndDoesNotReplaceRegularFile() throws {
        let directory = directory()
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? fm.removeItem(at: directory) }
        let bridge = AgentEventBridge(directory: directory)
        XCTAssertThrowsError(try bridge.start())
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data("user data".utf8).write(to: URL(fileURLWithPath: bridge.socketPath))
        XCTAssertThrowsError(try bridge.start())
        XCTAssertEqual(try String(contentsOfFile: bridge.socketPath, encoding: .utf8), "user data")
    }

    func testOversizedAndTimedOutClientsDoNotDeliver() async throws {
        let directory = directory()
        let bridge = AgentEventBridge(directory: directory)
        defer { bridge.stop(); try? FileManager.default.removeItem(at: directory) }
        try bridge.start()
        var deliveries = 0
        bridge.onEvent = { _ in deliveries += 1 }
        let fd = try connect(to: bridge)
        let oversized = [UInt8](repeating: 32, count: 4097)
        _ = Darwin.write(fd, oversized, oversized.count)
        Darwin.close(fd)
        // A separate valid client confirms the read loop drained preceding input.
        let valid = expectation(description: "valid client")
        bridge.onEvent = { _ in deliveries += 1; valid.fulfill() }
        let validFD = try connect(to: bridge)
        let payload = Array("{}\n".utf8)
        _ = Darwin.write(validFD, payload, payload.count)
        Darwin.close(validFD)
        await fulfillment(of: [valid], timeout: 2)
        XCTAssertEqual(deliveries, 1)
        let idle = try connect(to: bridge)
        defer { Darwin.close(idle) }
        await Task.yield()
        bridge.maintain(now: Date().addingTimeInterval(3))
        XCTAssertEqual(deliveries, 1)
    }
}
