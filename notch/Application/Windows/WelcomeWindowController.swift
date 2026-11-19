internal import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 570),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Welcome to Notch"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(agents: AIAgentsViewModel) {
        window?.contentView = NSHostingView(rootView: WelcomeView(agents: agents, close: { [weak self] in self?.close() }))
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct WelcomeView: View {
    @ObservedObject var agents: AIAgentsViewModel
    let close: () -> Void
    @State private var showAgents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image("notchbrand").resizable().scaledToFit().frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meet Notch.").font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("Your Mac’s quiet companion.").foregroundStyle(.secondary)
                    Text("by infynite").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            instruction("1", "Look up, not around.", "Notch lives at the top center of your screen. Play music or change the volume to see it respond.")
            instruction("2", "One icon. All your settings.", "Left-click the small rectangle in the top-right menu bar → Settings. You can also right-click the overlay.")
            instruction("3", "Keep your agents in sight.", "Connect OpenCode, Codex, or Claude Code to see when they’re working, need attention, or finish a turn.")
            Text("Press and hold an activity to expand it. Closing a window keeps Notch running; choose Quit from the menu-bar menu to stop it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Settings") { SettingsWindowController.shared.showWindow() }
                Button("Connect agents") { showAgents = true }
                Spacer()
                Button("Got it") {
                    UserDefaults.standard.set(true, forKey: "welcome.seen")
                    close()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 540, height: 570)
        .tint(.primary)
        .sheet(isPresented: $showAgents) {
            VStack {
                AIAgentsSettingsView(viewModel: agents)
                Button("Done") { showAgents = false }.padding(.bottom)
            }.frame(width: 650, height: 700)
        }
    }

    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.caption.monospaced().weight(.semibold))
                .frame(width: 26, height: 26).background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
