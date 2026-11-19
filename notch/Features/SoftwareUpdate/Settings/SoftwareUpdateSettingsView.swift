//
//  SoftwareUpdateSettingsView.swift
//  notch
//
//  Created by Евгений Петрукович on 7/13/26.
//

import SwiftUI

struct SoftwareUpdateSettingsView: View {
    @ObservedObject private var updater = SparkleUpdater.shared
    var isEmbedded = false
    
    private var currentVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "\(version)"
    }
    
    var body: some View {
        Group {
            if isEmbedded {
                content
            } else {
                SettingsPageScrollView { content }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        versionCard
        optionsCard
    }
    
    private var versionCard: some View {
        SettingsCard {
            SettingsButtonRow(
                title: "Notch",
                description: "Version \(currentVersion)",
                imageName: "simplifiedLogo",
                iconSize: 30,
                color: .clear,
                buttonTitle: "settings.update.checkNow",
                isButtonDisabled: !updater.canCheckForUpdates,
                accessibilityIdentifier: "settings.update.versionCard"
            ) {
                updater.checkForUpdates()
            }
        }
    }
    
    private var optionsCard: some View {
        SettingsCard {
            SettingsToggleRow(
                title: "settings.update.autoCheck.title",
                description: "settings.update.autoCheck.desc",
                systemImage: "bell.badge.fill",
                color: .primary,
                isOn: $updater.automaticallyChecksForUpdates,
                accessibilityIdentifier: "settings.update.automaticallyChecks"
            )
            
            Divider()
                .opacity(0.6)
                .padding(.leading, 43)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            SettingsToggleRow(
                title: "settings.update.autoDownload.title",
                description: "settings.update.autoDownload.desc",
                systemImage: "arrow.down.circle.dotted",
                color: .primary,
                isOn: $updater.automaticallyDownloadsUpdates,
                accessibilityIdentifier: "settings.update.automaticallyDownloads"
            )
            .disabled(!updater.automaticallyChecksForUpdates)
            .opacity(!updater.automaticallyChecksForUpdates ? 0.5 : 1)
            Text("Updates come only from infynitehq/notch and must have a valid Notch signature. Local builds are not Apple-notarized.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
