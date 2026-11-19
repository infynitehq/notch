import XCTest
@testable import notch

@MainActor
final class AIAgentsViewModelTests: XCTestCase {
    func testOptInPrivacyProviderFilteringAndCompletionExpiry() throws {
        let suite = "AIAgentsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date()
        let viewModel = AIAgentsViewModel(defaults: defaults, now: { now })
        let started = AgentBridgeEvent(version: 1, eventID: "start", provider: .codex,
                                       sessionID: "one", kind: .started,
                                       timestamp: now.timeIntervalSince1970 * 1000, project: "Secret project")
        let data = try JSONEncoder().encode(started)
        XCTAssertFalse(viewModel.enabled)
        XCTAssertFalse(viewModel.showProjectNames)
        viewModel.receive(data)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        viewModel.enabled = true
        viewModel.receive(data)
        XCTAssertEqual(viewModel.visibleSessions.count, 1)
        XCTAssertEqual(viewModel.label(for: try XCTUnwrap(viewModel.featured)), "Codex")
        viewModel.showProjectNames = true
        XCTAssertEqual(viewModel.label(for: try XCTUnwrap(viewModel.featured)), "Secret project")
        now = now.addingTimeInterval(1)
        let completed = AgentBridgeEvent(version: 1, eventID: "done", provider: .codex,
                                         sessionID: "one", kind: .completed,
                                         timestamp: now.timeIntervalSince1970 * 1000)
        viewModel.receive(try JSONEncoder().encode(completed))
        XCTAssertEqual(viewModel.featured?.status, .completed)
        now = now.addingTimeInterval(9)
        viewModel.maintain()
        XCTAssertNil(viewModel.featured)
        XCTAssertEqual(viewModel.sessions.count, 1)
        viewModel.disabledProviders.insert(.codex)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        viewModel.receive(data)
        XCTAssertTrue(viewModel.sessions.isEmpty)
    }

    func testInvalidMessagesAreCountedWithoutPayloadLogging() {
        let suite = "AIAgentsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewModel = AIAgentsViewModel(defaults: defaults)
        viewModel.enabled = true
        viewModel.receive(Data("garbage".utf8))
        XCTAssertEqual(viewModel.rejectedEvents, 1)
        XCTAssertNil(viewModel.lastEventAt)
    }
}
