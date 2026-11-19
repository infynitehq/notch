import Foundation

enum CodingAgentProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, opencode
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }
}

enum AgentSessionStatus: String {
    case idle, working, attention, completed, failed, disconnected
    var title: String {
        switch self {
        case .idle: "Ready"
        case .working: "Working"
        case .attention: "Needs your attention"
        case .completed: "Turn finished"
        case .failed: "Turn failed"
        case .disconnected: "Status unknown"
        }
    }
    var symbol: String {
        switch self {
        case .idle: "terminal"
        case .working: "ellipsis.circle"
        case .attention: "hand.raised.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .disconnected: "questionmark.circle"
        }
    }
    var rank: Int {
        switch self {
        case .attention: 0
        case .failed: 1
        case .working: 2
        case .completed: 3
        case .disconnected: 4
        case .idle: 5
        }
    }
}

/// A deliberately metadata-only, versioned wire format. Times are Unix milliseconds.
struct AgentBridgeEvent: Codable {
    enum Kind: String, Codable {
        case idle, started, activity, attention, completed, failed, ended, heartbeat
    }
    let version: Int
    let eventID: String
    let provider: CodingAgentProvider
    let sessionID: String
    let kind: Kind
    let timestamp: Double
    var project: String?
    var origin: String?

    static let maximumBytes = 4096

    static func decode(_ data: Data, now: Date) throws -> Self {
        guard data.count <= maximumBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: [
                "version", "eventID", "provider", "sessionID", "kind", "timestamp", "project", "origin"
              ]) else { throw ValidationError.invalid }
        let event = try JSONDecoder().decode(Self.self, from: data)
        guard event.isValid(now: now) else { throw ValidationError.invalid }
        return event
    }

    func isValid(now: Date) -> Bool {
        version == 1 && timestamp.isFinite &&
        abs(timestamp / 1000 - now.timeIntervalSince1970) <= 120 &&
        Self.validID(eventID) && Self.validID(sessionID) &&
        (project?.utf8.count ?? 0) <= 256 && (origin?.utf8.count ?? 0) <= 100
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 200 &&
        value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)
        }
    }
    enum ValidationError: Error { case invalid }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    let provider: CodingAgentProvider
    let sessionID: String
    var project: String
    var origin: String?
    var status: AgentSessionStatus
    var startedAt: Date
    var updatedAt: Date
    var lastTimestamp: Double
    var dismissed = false
    var ended = false
}

/// Owns ordering, bounded deduplication, expiry and dismissal independently of presentation.
@MainActor
final class AgentSessionStore {
    private(set) var sessions: [String: AgentSession] = [:]
    private var seen = Set<String>()
    private var seenOrder: [String] = []
    static let maximumSessions = 64

    var sortedSessions: [AgentSession] {
        sessions.values.sorted {
            if $0.status.rank != $1.status.rank { return $0.status.rank < $1.status.rank }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    @discardableResult
    func ingest(_ event: AgentBridgeEvent, now: Date) -> Bool {
        guard event.isValid(now: now) else { return false }
        let dedupID = "\(event.provider.rawValue):\(event.eventID)"
        guard !seen.contains(dedupID) else { return false }
        seen.insert(dedupID)
        seenOrder.append(dedupID)
        if seenOrder.count > 2048 { seen.remove(seenOrder.removeFirst()) }

        let key = "\(event.provider.rawValue):\(event.sessionID)"
        var session = sessions[key]
        guard event.timestamp > (session?.lastTimestamp ?? -.infinity) else { return false }
        // A heartbeat cannot create or revive a session.
        if event.kind == .heartbeat && session == nil { return false }
        if session == nil {
            if sessions.count >= Self.maximumSessions {
                // Never evict a working/attention session to make room for incoming noise.
                guard let oldest = sessions.values.filter({
                    $0.status != .working && $0.status != .attention
                }).min(by: { $0.updatedAt < $1.updatedAt }) else { return false }
                sessions.removeValue(forKey: oldest.id)
            }
            session = AgentSession(
                id: key, provider: event.provider, sessionID: event.sessionID,
                project: "Project", status: .idle, startedAt: now, updatedAt: now,
                lastTimestamp: event.timestamp
            )
        }
        guard var value = session else { return false }
        let previous = value.status
        var refreshTime = true
        switch event.kind {
        case .idle:
            // SessionStart can also fire during compaction; don't erase active work.
            refreshTime = previous == .idle
        case .started:
            value.status = .working
            value.startedAt = now
            value.dismissed = false
            value.ended = false
        case .activity:
            // Late tool callbacks must not resurrect a finished turn.
            if !value.ended && (previous == .idle || previous == .working || previous == .attention || previous == .disconnected) {
                value.status = .working
            } else { refreshTime = false }
        case .attention:
            if !value.ended && previous != .completed && previous != .failed {
                value.status = .attention
                if previous != .attention { value.dismissed = false }
            } else { refreshTime = false }
        case .completed:
            if previous != .failed && !value.ended { value.status = .completed }
            refreshTime = previous != .completed && previous != .failed && !value.ended
        case .failed:
            if !value.ended { value.status = .failed }
            refreshTime = previous != .failed && !value.ended
        case .ended:
            value.status = .disconnected
            value.ended = true
        case .heartbeat:
            refreshTime = previous == .working || previous == .attention
        }
        if let project = event.project {
            // Never display full paths or control/bidi characters from an untrusted sender.
            let basename = (project as NSString).lastPathComponent
            value.project = String(String.UnicodeScalarView(basename.unicodeScalars.filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar) && !CharacterSet.illegalCharacters.contains(scalar) &&
                ![0x202A...0x202E, 0x2066...0x2069].contains(where: { $0.contains(Int(scalar.value)) })
            }.prefix(80)))
            if value.project.isEmpty { value.project = "Project" }
        }
        if let origin = event.origin { value.origin = AgentOrigin.allowed.contains(origin) ? origin : nil }
        value.lastTimestamp = event.timestamp
        // Heartbeats renew liveness, not completion visibility.
        if refreshTime {
            value.updatedAt = now
        }
        sessions[key] = value
        return true
    }

    func maintain(now: Date) {
        for (id, var value) in sessions {
            let age = now.timeIntervalSince(value.updatedAt)
            if age > 3600 {
                sessions.removeValue(forKey: id)
            } else if age > 900 && (value.status == .working || value.status == .attention) {
                value.status = .disconnected
                sessions[id] = value
            }
        }
    }

    func dismiss(_ id: String) { sessions[id]?.dismissed = true }
    func remove(provider: CodingAgentProvider) {
        sessions = sessions.filter { $0.value.provider != provider }
    }
    func clear() {
        sessions.removeAll()
        seen.removeAll()
        seenOrder.removeAll()
    }
}

enum AgentOrigin {
    // Only activate already-running, known applications. Never execute incoming commands or URLs.
    static let allowed: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "ai.opencode.desktop", "com.anthropic.claudefordesktop", "com.openai.codex"
    ]
}
