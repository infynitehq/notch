import SwiftUI

private struct ShowsAIAgentContentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showsAIAgentContent: Bool {
        get { self[ShowsAIAgentContentKey.self] }
        set { self[ShowsAIAgentContentKey.self] = newValue }
    }
}

struct AIAgentNotchContent: NotchContentProtocol {
    let viewModel: AIAgentsViewModel
    let id = NotchContentRegistry.AIAgents.active.id
    var priority: Int {
        viewModel.needsAttention ? 11 : NotchContentRegistry.AIAgents.active.priority
    }
    var isExpandable: Bool { true }
    func compactSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth + 100, height: baseHeight)
    }
    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: max(baseWidth + 200, 400), height: baseHeight + 215)
    }
    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) { (24, 30) }
    @MainActor func compactView() -> AnyView {
        AnyView(AIAgentCompactView(viewModel: viewModel))
    }
    @MainActor func expandedView() -> AnyView {
        AnyView(AIAgentExpandedView(viewModel: viewModel))
    }
}

extension AgentSessionStatus {
    var color: Color {
        switch self {
        case .working: .cyan
        case .attention: .orange
        case .completed: .green
        case .failed: .red
        case .idle, .disconnected: .secondary
        }
    }
}

private struct AIAgentCompactView: View {
    @ObservedObject var viewModel: AIAgentsViewModel
    @Environment(\.notchScale) private var notchScale
    @Environment(\.showsAIAgentContent) private var showsContent
    var body: some View {
        HStack {
            if showsContent, let session = viewModel.featured {
                Image(systemName: session.status.symbol)
                    .foregroundStyle(session.status.color)
                Spacer(minLength: 10)
                Text("\(viewModel.visibleSessions.count)")
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 14.scaled(by: notchScale))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsContent ? (viewModel.featured.map {
            "\($0.provider.title), \($0.status.title), \(viewModel.visibleSessions.count) sessions"
        } ?? "AI agents") : "")
    }
}

struct AIAgentExpandedView: View {
    @ObservedObject var viewModel: AIAgentsViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.showsAIAgentContent) private var showsContent
    var body: some View {
        if showsContent { content }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI agents", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button("Manage") { openWindow(id: "ai-agents") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.sessions.filter { !$0.dismissed }) { session in
                        HStack(spacing: 10) {
                            Image(systemName: session.status.symbol)
                                .foregroundStyle(session.status.color)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(viewModel.label(for: session)).fontWeight(.medium).lineLimit(1)
                                Text("\(session.provider.title) · \(session.status.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if session.status == .working {
                                Text(session.startedAt, style: .timer)
                                    .font(.caption.monospacedDigit())
                                    .frame(maxWidth: 65)
                            }
                            Button { viewModel.openOrigin(for: session) } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .help("Open originating app (select the session there)")
                            .accessibilityLabel("Open \(session.provider.title)")
                            Button { viewModel.dismiss(session.id) } label: {
                                Image(systemName: "xmark")
                            }
                            .help("Dismiss until the next turn or new attention request")
                            .accessibilityLabel("Dismiss \(session.provider.title) session")
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            if let message = viewModel.navigationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .padding(.top, 8)
        .preferredColorScheme(.dark)
    }
}
