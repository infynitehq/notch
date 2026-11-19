internal import AppKit
import Combine
import Foundation

@MainActor
final class AIAgentsViewModel: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var bridgeStatus = "Disabled"
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var rejectedEvents = 0
    @Published private(set) var navigationMessage: String?
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "aiAgents.enabled")
            if hasStarted { configureBridge() }
            else if !enabled { store.clear(); refresh() }
        }
    }
    @Published var showProjectNames: Bool {
        didSet { defaults.set(showProjectNames, forKey: "aiAgents.showProjectNames") }
    }
    @Published var showCompletions: Bool {
        didSet { defaults.set(showCompletions, forKey: "aiAgents.showCompletions") }
    }
    @Published var disabledProviders: Set<CodingAgentProvider> {
        didSet {
            defaults.set(disabledProviders.map(\.rawValue), forKey: "aiAgents.disabledProviders")
            for provider in disabledProviders { store.remove(provider: provider) }
            refresh()
        }
    }
    private let store: AgentSessionStore
    private let bridge: AgentEventBridge
    private let defaults: UserDefaults
    private let now: () -> Date
    private var timer: AnyCancellable?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard, bridge: AgentEventBridge? = nil,
         store: AgentSessionStore? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.bridge = bridge ?? AgentEventBridge()
        self.store = store ?? AgentSessionStore()
        self.now = now
        self.enabled = defaults.bool(forKey: "aiAgents.enabled")
        self.showProjectNames = defaults.bool(forKey: "aiAgents.showProjectNames")
        self.showCompletions = defaults.object(forKey: "aiAgents.showCompletions") as? Bool ?? true
        self.disabledProviders = Set((defaults.stringArray(forKey: "aiAgents.disabledProviders") ?? []).compactMap(CodingAgentProvider.init))
    }

    var socketPath: String { bridge.socketPath }
    var visibleSessions: [AgentSession] {
        sessions.filter {
            guard !$0.dismissed else { return false }
            switch $0.status {
            case .working, .attention: return true
            case .failed, .completed:
                return showCompletions && now().timeIntervalSince($0.updatedAt) < 8
            case .idle, .disconnected: return false
            }
        }
    }
    var featured: AgentSession? { visibleSessions.first }
    var needsAttention: Bool { visibleSessions.contains { $0.status == .attention } }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        bridge.onEvent = { [weak self] data in self?.receive(data) }
        bridge.onRejectedMessage = { [weak self] in self?.recordRejection() }
        configureBridge()
    }

    func stop() {
        hasStarted = false
        timer = nil
        bridge.stop()
        store.clear()
        refresh()
        bridgeStatus = "Disabled"
    }

    func retry() { if hasStarted { configureBridge() } }

    private func configureBridge() {
        timer = nil
        bridge.stop()
        store.clear()
        refresh()
        guard enabled else { bridgeStatus = "Disabled"; return }
        do {
            try bridge.start()
            bridgeStatus = "Listening locally"
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                self?.maintain()
            }
        } catch {
            bridgeStatus = error.localizedDescription
        }
    }

    func receive(_ data: Data) {
        guard enabled else { return }
        do {
            let event = try AgentBridgeEvent.decode(data, now: now())
            guard !disabledProviders.contains(event.provider) else { return }
            if store.ingest(event, now: now()) {
                lastEventAt = now()
                refresh()
            }
        } catch {
            recordRejection()
        }
    }

    func maintain() {
        store.maintain(now: now())
        bridge.maintain(now: now())
        refresh()
    }

    func dismiss(_ id: String) { store.dismiss(id); refresh() }
    func clearSessions() { store.clear(); refresh() }
    func label(for session: AgentSession) -> String {
        showProjectNames ? session.project : session.provider.title
    }

    func openOrigin(for session: AgentSession) {
        guard let origin = session.origin, AgentOrigin.allowed.contains(origin),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: origin).first,
              app.activate(options: []) else {
            navigationMessage = "The originating app isn't available. Return to your agent manually."
            return
        }
        navigationMessage = "Opened \(app.localizedName ?? "app"). Select the session in that app."
    }

    private func refresh() { sessions = store.sortedSessions }
    private func recordRejection() { rejectedEvents = min(rejectedEvents + 1, 1_000_000) }
}
