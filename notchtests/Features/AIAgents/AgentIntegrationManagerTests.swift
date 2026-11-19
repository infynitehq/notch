import XCTest
@testable import notch

@MainActor
final class AgentIntegrationManagerTests: XCTestCase {
    func testBundledNodeAdaptersReachNativeReceiverForAllProviders() async throws {
        let node = try await AgentIntegrationManager.run("/bin/zsh", ["-lc", "command -v node || true"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard node.hasPrefix("/") else { throw XCTSkip("Node.js is not installed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notch-bridge-\(UUID().uuidString)")
        let suite = "in.infynite.notch.tests.bridge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let bridge = AgentEventBridge(directory: directory)
        let model = AIAgentsViewModel(defaults: defaults, bridge: bridge)
        model.enabled = true
        model.start()
        defer { model.stop() }
        XCTAssertEqual(model.bridgeStatus, "Listening locally")
        let script = try XCTUnwrap(Bundle.main.url(forResource: "bridge", withExtension: "mjs"))
        let javascript = """
        const { makeEvent, sendEvent } = await import(process.argv[1]);
        const ok = await sendEvent(makeEvent(process.argv[3], "native-e2e", "started"), process.argv[2]);
        if (!ok) process.exit(1);
        """
        for provider in CodingAgentProvider.allCases {
            _ = try await AgentIntegrationManager.run(node, [
                "--input-type=module", "-e", javascript, script.absoluteString,
                bridge.socketPath, provider.rawValue
            ])
        }
        // Socket delivery is asynchronous; this polls only in a bounded application test.
        for _ in 0..<100 where model.sessions.count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(Set(model.sessions.map(\.provider)), Set(CodingAgentProvider.allCases))
        XCTAssertTrue(model.sessions.allSatisfy { $0.status == .working })
        XCTAssertNotNil(model.lastEventAt)
        XCTAssertEqual(model.rejectedEvents, 0)
    }
}
