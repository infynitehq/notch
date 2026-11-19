import SwiftUI

struct SupportSettingsView: View {
    let onRequestInternetAccess: () -> Bool

    var body: some View {
        SettingsPageScrollView {
            SettingsCard {
                Label("Help make Notch better", systemImage: "heart")
                    .font(.headline)
                Text("Report a bug, suggest an improvement, or contribute to Notch by infynite.")
                    .foregroundStyle(.secondary)
                Link("Issues & feature requests", destination: URL(string: "https://github.com/infynitehq/notch/issues")!)
                Link("Contribute on GitHub", destination: URL(string: "https://github.com/infynitehq/notch")!)
            }
        }
    }
}
