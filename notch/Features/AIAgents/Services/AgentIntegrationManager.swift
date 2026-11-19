internal import AppKit
import Combine
import Foundation

/// Owns connection setup, not agent execution or approval decisions.
@MainActor
final class AgentIntegrationManager: ObservableObject {
    @Published private(set) var nodePath: String?
    @Published private(set) var detected: Set<CodingAgentProvider> = []
    @Published private(set) var installed: Set<CodingAgentProvider> = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    private let home: URL
    private let resources: Bundle
    private var kit: URL {
        home.appendingPathComponent("Library/Application Support/in.infynite.notch/agents")
    }
    static let kitFiles = [
        "bridge.mjs", "opencode.mjs", "opencode-events.mjs", "opencode-runtime.mjs",
        "opencode-config.mjs", "package.json", "README-AI-AGENTS.md"
    ]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, resources: Bundle = .main) {
        self.home = home
        self.resources = resources
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            nodePath = try await Self.findExecutable("node")
            detected.removeAll()
            for provider in CodingAgentProvider.allCases {
                let command = provider == .opencode ? "opencode" : provider.rawValue
                if (try? await Self.findExecutable(command)) != nil {
                    detected.insert(provider)
                }
            }
            guard let nodePath else {
                message = "Node.js 18 or later is needed to connect agents. Install Node.js, then refresh."
                return
            }
            try await Self.validateNode(nodePath)
            try installKit()
            let output = try await Self.run(nodePath, [kit.appendingPathComponent("bridge.mjs").path, "doctor"])
            let data = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            let values = data?["installed"] as? [String: Bool] ?? [:]
            installed = Set(CodingAgentProvider.allCases.filter { values[$0.rawValue] == true })
        } catch { message = error.localizedDescription }
    }

    func configure(_ provider: CodingAgentProvider, disconnect: Bool = false) async {
        guard !busy, let nodePath else { return }
        busy = true
        defer { busy = false }
        do {
            try installKit()
            let output = try await Self.run(nodePath, [
                kit.appendingPathComponent("bridge.mjs").path,
                disconnect ? "uninstall" : "install", provider.rawValue
            ])
            if disconnect { installed.remove(provider) } else { installed.insert(provider) }
            message = output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { message = error.localizedDescription }
    }

    func verify(_ provider: CodingAgentProvider) async {
        guard !busy, let nodePath else { return }
        busy = true
        defer { busy = false }
        do {
            message = try await Self.run(nodePath, [kit.appendingPathComponent("bridge.mjs").path, "test", provider.rawValue])
        } catch { message = error.localizedDescription }
    }

    func chooseNode() {
        let panel = NSOpenPanel()
        panel.message = "Choose the Node.js executable (Node.js 18 or later)."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await Self.validateNode(url.path)
                    nodePath = url.resolvingSymlinksInPath().path
                    try installKit()
                    message = "Node.js selected. You can now connect your agents."
                } catch { message = error.localizedDescription }
            }
        }
    }

    private func installKit() throws {
        let fm = FileManager.default
        // Never follow a redirected application-managed directory.
        for directory in [kit.deletingLastPathComponent(), kit] where fm.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw SetupError("The Notch integration directory is not a regular directory.")
            }
        }
        let files = try Self.kitFiles.map { name -> (String, Data) in
            guard let url = resources.url(forResource: name, withExtension: nil) ??
                    resources.url(forResource: name, withExtension: nil, subdirectory: "AIAgentIntegrations") else {
                throw SetupError("The app is missing \(name). Reinstall Notch.")
            }
            return (name, try Data(contentsOf: url))
        }
        try fm.createDirectory(at: kit, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (name, data) in files {
            try data.write(to: kit.appendingPathComponent(name), options: .atomic)
        }
    }

    private nonisolated static func findExecutable(_ name: String) async throws -> String? {
        // The command is a fixed provider name, never supplied by an event or user input.
        let value = try await run("/bin/zsh", ["-lc", "command -v \(name) || true"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: value) else { return nil }
        return URL(fileURLWithPath: value).resolvingSymlinksInPath().path
    }

    private nonisolated static func validateNode(_ executable: String) async throws {
        let version = try await run(executable, ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("v"),
              let major = Int(version.dropFirst().split(separator: ".").first ?? ""),
              major >= 18 else {
            throw SetupError("Choose a Node.js executable, version 18 or later.")
        }
    }

    nonisolated static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            let text = String(decoding: data.prefix(16_384), as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw SetupError(text.isEmpty ? "Agent setup failed or timed out. Try again." : text)
            }
            return text
        }.value
    }

    struct SetupError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
