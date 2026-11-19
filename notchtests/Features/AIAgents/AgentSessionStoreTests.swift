import XCTest
@testable import notch

@MainActor
final class AgentSessionStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private func event(_ kind: AgentBridgeEvent.Kind = .started, id: String = UUID().uuidString,
                       session: String = "session-1", provider: CodingAgentProvider = .codex,
                       offset: Double = 0) -> AgentBridgeEvent {
        AgentBridgeEvent(version: 1, eventID: id, provider: provider, sessionID: session,
                         kind: kind, timestamp: now.timeIntervalSince1970 * 1000 + offset)
    }

    func testDuplicateAndOutOfOrderEventsAreIgnored() {
        let store = AgentSessionStore()
        let started = event(id: "one", offset: 10)
        XCTAssertTrue(store.ingest(started, now: now))
        XCTAssertFalse(store.ingest(started, now: now))
        XCTAssertFalse(store.ingest(event(.attention, offset: 5), now: now))
        XCTAssertEqual(store.sortedSessions.first?.status, .working)
    }

    func testLateToolAndAttentionCannotResurrectFinishedTurn() {
        for terminal in [AgentBridgeEvent.Kind.completed, .failed] {
            let store = AgentSessionStore()
            store.ingest(event(), now: now)
            store.ingest(event(terminal, offset: 10), now: now)
            store.ingest(event(.activity, offset: 20), now: now)
            store.ingest(event(.attention, offset: 30), now: now)
            XCTAssertEqual(store.sortedSessions.first?.status, terminal == .completed ? .completed : .failed)
            store.ingest(event(.started, offset: 40), now: now)
            XCTAssertEqual(store.sortedSessions.first?.status, .working)
        }
    }

    func testSessionStartDuringCompactionDoesNotEraseWork() {
        let store = AgentSessionStore()
        store.ingest(event(.started), now: now)
        store.ingest(event(.idle, offset: 1), now: now)
        XCTAssertEqual(store.sortedSessions.first?.status, .working)
    }

    func testSameRepositoryAndProviderSessionIDsDoNotCollide() {
        let store = AgentSessionStore()
        store.ingest(event(), now: now)
        store.ingest(event(session: "session-2"), now: now)
        store.ingest(event(provider: .claude), now: now)
        XCTAssertEqual(store.sessions.count, 3)
    }

    func testAttentionSortsFirstAndDismissalSticksUntilNewAttentionTransition() {
        let store = AgentSessionStore()
        store.ingest(event(session: "working"), now: now)
        store.ingest(event(.attention, session: "waiting"), now: now)
        let id = store.sortedSessions[0].id
        XCTAssertEqual(id, "codex:waiting")
        store.dismiss(id)
        store.ingest(event(.heartbeat, session: "waiting", offset: 1), now: now)
        store.ingest(event(.attention, session: "waiting", offset: 2), now: now)
        XCTAssertEqual(store.sessions[id]?.dismissed, true)
        store.ingest(event(.activity, session: "waiting", offset: 3), now: now)
        store.ingest(event(.attention, session: "waiting", offset: 4), now: now)
        XCTAssertEqual(store.sessions[id]?.dismissed, false)
    }

    func testHeartbeatCannotCreateOrReviveSession() {
        let store = AgentSessionStore()
        XCTAssertFalse(store.ingest(event(.heartbeat), now: now))
        store.ingest(event(.started), now: now)
        store.ingest(event(.ended, offset: 1), now: now)
        store.ingest(event(.heartbeat, offset: 2), now: now)
        store.ingest(event(.activity, offset: 3), now: now)
        store.ingest(event(.attention, offset: 4), now: now)
        XCTAssertEqual(store.sortedSessions.first?.status, .disconnected)
    }

    func testLateCallbacksDoNotExtendCompletionVisibility() {
        let store = AgentSessionStore()
        store.ingest(event(.completed), now: now)
        store.ingest(event(.activity, offset: 10_000), now: now.addingTimeInterval(10))
        store.ingest(event(.completed, offset: 11_000), now: now.addingTimeInterval(11))
        XCTAssertEqual(store.sortedSessions.first?.updatedAt, now)
    }

    func testExpiryIsUnknownNotFailureAndEventuallyPrunes() {
        let store = AgentSessionStore()
        store.ingest(event(), now: now)
        store.maintain(now: now.addingTimeInterval(901))
        XCTAssertEqual(store.sortedSessions.first?.status, .disconnected)
        store.maintain(now: now.addingTimeInterval(3601))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testHeartbeatRenewsWorkingLiveness() {
        let store = AgentSessionStore()
        store.ingest(event(), now: now)
        var heartbeat = event(.heartbeat, offset: 850_000)
        let later = now.addingTimeInterval(850)
        // A heartbeat is accepted only relative to its actual receipt time.
        heartbeat.project = nil
        store.ingest(heartbeat, now: later)
        store.maintain(now: now.addingTimeInterval(901))
        XCTAssertEqual(store.sortedSessions.first?.status, .working)
    }

    func testCapacityNeverEvictsActiveSessions() {
        let store = AgentSessionStore()
        for index in 0..<100 { store.ingest(event(session: "session-\(index)"), now: now) }
        XCTAssertEqual(store.sessions.count, AgentSessionStore.maximumSessions)
        XCTAssertNotNil(store.sessions["codex:session-0"])
    }

    func testPrivacySanitizesLabelsAndRejectsUnknownOrigins() {
        let store = AgentSessionStore()
        var value = event()
        value.project = "/private/company/hello\u{202E}\nworld"
        value.origin = "https://evil.example"
        store.ingest(value, now: now)
        XCTAssertEqual(store.sortedSessions.first?.project, "helloworld")
        XCTAssertNil(store.sortedSessions.first?.origin)
    }

    func testWireValidationRejectsUnknownFieldsVersionsAndOversizedPayloads() throws {
        let valid = try JSONEncoder().encode(event())
        XCTAssertNoThrow(try AgentBridgeEvent.decode(valid, now: now))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["prompt"] = "sensitive"
        XCTAssertThrowsError(try AgentBridgeEvent.decode(JSONSerialization.data(withJSONObject: object), now: now))
        object.removeValue(forKey: "prompt")
        object["version"] = 2
        XCTAssertThrowsError(try AgentBridgeEvent.decode(JSONSerialization.data(withJSONObject: object), now: now))
        XCTAssertThrowsError(try AgentBridgeEvent.decode(Data(repeating: 32, count: 4097), now: now))
        XCTAssertThrowsError(try AgentBridgeEvent.decode(Data("not JSON".utf8), now: now))
        XCTAssertFalse(event(offset: -121_000).isValid(now: now))
        XCTAssertFalse(event(offset: 121_000).isValid(now: now))
        XCTAssertFalse(event(session: "../escape").isValid(now: now))
    }

    func testRemoveProviderLeavesOthersUntouched() {
        let store = AgentSessionStore()
        store.ingest(event(provider: .codex), now: now)
        store.ingest(event(provider: .claude), now: now)
        store.remove(provider: .codex)
        XCTAssertEqual(store.sortedSessions.map(\.provider), [.claude])
    }
}
