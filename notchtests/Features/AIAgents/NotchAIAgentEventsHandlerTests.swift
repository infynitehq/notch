import XCTest
@testable import notch

@MainActor
final class NotchAIAgentEventsHandlerTests: XCTestCase {
    func testActivityIsRemovedWhileLockedAndRestoredAfterUnlock() async throws {
        let suite = "AIAgentHandlerTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsViewModel(defaults: defaults)
        let notch = NotchViewModel(settings: settings.application, hideDelay: 0.01, queueDelay: 0)
        let lock = LockScreenManager(service: InactiveLockScreenMonitoringService(),
                                    soundPlayer: InactiveLockScreenSoundPlayer(), defaults: defaults)
        let model = AIAgentsViewModel(defaults: defaults)
        let handler = NotchAIAgentEventsHandler(viewModel: model, notch: notch, lockScreen: lock)
        defer { withExtendedLifetime(handler) {} }
        model.enabled = true
        let event = AgentBridgeEvent(version: 1, eventID: "one", provider: .codex,
                                    sessionID: "one", kind: .attention,
                                    timestamp: Date().timeIntervalSince1970 * 1000)
        model.receive(try JSONEncoder().encode(event))
        await assertEventually {
            await MainActor.run { notch.notchModel.content?.id == NotchContentRegistry.AIAgents.active.id }
        }
        lock.setDebugLockState(true)
        await assertEventually {
            await MainActor.run { notch.notchModel.content?.id != NotchContentRegistry.AIAgents.active.id }
        }
        lock.setDebugLockState(false)
        await assertEventually {
            await MainActor.run { notch.notchModel.content?.id == NotchContentRegistry.AIAgents.active.id }
        }
        model.disabledProviders.insert(.codex)
        await assertEventually {
            await MainActor.run { notch.notchModel.content?.id != NotchContentRegistry.AIAgents.active.id }
        }
    }

    func testPriorityYieldsForWorkAndElevatesAttentionBelowSystemOverlays() throws {
        let suite = "AIAgentPriorityTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AIAgentsViewModel(defaults: defaults)
        model.enabled = true
        let now = Date().timeIntervalSince1970 * 1000
        func send(_ kind: AgentBridgeEvent.Kind, offset: Double) throws {
            model.receive(try JSONEncoder().encode(AgentBridgeEvent(
                version: 1, eventID: UUID().uuidString, provider: .claude,
                sessionID: "one", kind: kind, timestamp: now + offset
            )))
        }
        try send(.started, offset: 0)
        let content = AIAgentNotchContent(viewModel: model)
        XCTAssertLessThan(content.priority, NotchContentPriority.nowPlaying)
        try send(.attention, offset: 1)
        XCTAssertGreaterThan(content.priority, NotchContentPriority.screenRecording)
        XCTAssertLessThan(content.priority, NotchContentPriority.dragAndDrop)
        XCTAssertTrue(content.isExpandable)
    }
}
