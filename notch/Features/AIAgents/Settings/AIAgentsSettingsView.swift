internal import AppKit
import SwiftUI

struct AIAgentsSettingsView: View {
    @ObservedObject var viewModel: AIAgentsViewModel
    @StateObject private var integrations = AgentIntegrationManager()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "terminal").font(.system(size: 26, weight: .medium))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your agents, at a glance.").font(.title2.weight(.semibold))
                        Text("Working, waiting, finished. Right in your notch.")
                            .foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Toggle("Enable agent companion", isOn: $viewModel.enabled)
                    .accessibilityIdentifier("agents.enabled")
                LabeledContent("Local receiver", value: viewModel.bridgeStatus)
                if viewModel.enabled { Button("Retry receiver") { viewModel.retry() } }
            } footer: {
                Text("Status only. Notch never reads chats, collects API keys, or approves commands.")
            }

            Section {
                if integrations.busy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking agent connections…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(CodingAgentProvider.allCases) { provider in
                    providerRow(provider)
                }
            } header: { Text("Connect your agents") } footer: {
                Text("Connect installs a small local adapter and updates that agent’s settings with a backup. Your other settings are preserved. Agent approvals stay in the agent.")
            }

            if integrations.nodePath == nil {
                Section("Node.js required") {
                    Text("Install Node.js 18 or later, or choose an existing executable.")
                    Link("Get Node.js", destination: URL(string: "https://nodejs.org")!)
                    Button("Choose Node.js…") { integrations.chooseNode() }
                }
            }
            if let message = integrations.message {
                Section("Setup details") {
                    Text(message).font(.caption).textSelection(.enabled)
                }
            }
            Section("Presentation") {
                Toggle("Show project names", isOn: $viewModel.showProjectNames)
                Toggle("Show finished turns briefly", isOn: $viewModel.showCompletions)
                Text("Working status yields to music. Attention requests take priority. Status is hidden while your Mac is locked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Text(viewModel.socketPath).font(.caption.monospaced()).textSelection(.enabled)
                if let date = viewModel.lastEventAt {
                    LabeledContent("Last accepted event") { Text(date, style: .relative) }
                }
                LabeledContent("Rejected events", value: "\(viewModel.rejectedEvents)")
                Button("Refresh connections") { Task { await integrations.refresh() } }
                    .disabled(integrations.busy)
                Button("Clear session data") { viewModel.clearSessions() }
            }
            Section("Sessions (\(viewModel.sessions.count))") {
                if viewModel.sessions.isEmpty {
                    Text("Connect an agent, then send it a prompt. Live status will appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.sessions) { session in
                    HStack {
                        Label(viewModel.label(for: session), systemImage: session.status.symbol)
                        Spacer()
                        Text(session.status.title).foregroundStyle(.secondary)
                        Button("Open app") { viewModel.openOrigin(for: session) }
                    }
                }
                if let message = viewModel.navigationMessage { Text(message).font(.caption) }
            }
        }
        .formStyle(.grouped)
        .tint(.primary)
        .frame(minWidth: 600, minHeight: 570)
        .task { await integrations.refresh() }
    }

    private func providerRow(_ provider: CodingAgentProvider) -> some View {
        let installed = integrations.installed.contains(provider)
        let live = viewModel.sessions.contains { $0.provider == provider && !$0.sessionID.hasPrefix("test-") }
        let tested = viewModel.sessions.contains { $0.provider == provider && $0.sessionID.hasPrefix("test-") }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.title).font(.headline)
                    Text(live ? "Real activity received" : installed ? "Installed · waiting for activity" :
                            integrations.detected.contains(provider) ? "Detected · not connected" : "Not connected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if installed {
                    Button("Verify") { Task { await integrations.verify(provider) } }
                        .disabled(!viewModel.enabled)
                    Button("Disconnect") { Task { await integrations.configure(provider, disconnect: true) } }
                } else {
                    Button("Connect") {
                        viewModel.enabled = true
                        viewModel.disabledProviders.remove(provider)
                        Task { await integrations.configure(provider) }
                    }.buttonStyle(.borderedProminent)
                }
            }
            .disabled(integrations.busy || integrations.nodePath == nil)
            .accessibilityIdentifier("agents.provider.\(provider.rawValue)")
            if installed {
                Text(provider == .opencode
                     ? "OpenCode reloads configuration automatically. Use /reload if needed, then send a prompt."
                     : provider == .codex
                     ? "Review and trust the hooks in Codex /hooks or Settings → Hooks, then send a prompt."
                     : "Review the hooks in Claude Code, then start a new session and send a prompt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if tested { Label("Local test received. Real agent activity is still checked separately.", systemImage: "checkmark.circle").font(.caption) }
        }
        .padding(.vertical, 6)
    }
}
