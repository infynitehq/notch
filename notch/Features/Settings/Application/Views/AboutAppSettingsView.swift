import SwiftUI

struct AboutAppSettingsView: View {
    @ObservedObject var applicationSettings: ApplicationSettingsStore
    let onRequestInternetAccess: () -> Bool

    var body: some View {
        SettingsPageScrollView {
            VStack(spacing: 12) {
                Image("notchbrand").resizable().scaledToFit().frame(width: 88, height: 88)
                Text("Notch").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("A little space. A lot happening.").font(.headline)
                Text("A native notch companion for your Mac.\nMade by infynite.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(AppVersionText.appVersionText).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)

            SoftwareUpdateSettingsView(isEmbedded: true)

            SettingsCard {
                Link("Notch on GitHub", destination: URL(string: "https://github.com/infynitehq/notch")!)
                Link("Report an issue", destination: URL(string: "https://github.com/infynitehq/notch/issues")!)
                Link("infynite", destination: URL(string: "https://infynite.in")!)
                Divider()
                Text("Open-source software · GNU GPL v3").font(.caption).foregroundStyle(.secondary)
                Text("Based on DynamicNotch by Evgeniy Petrukovich and contributors. Original copyright notices and license are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Upstream source & attribution", destination: URL(string: "https://github.com/jackson-storm/DynamicNotch")!)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("settings.about.root")
    }
}
