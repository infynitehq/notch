//
//  AppDelegate.swift
//  notch
//
//  Created by Евгений Петрукович on 2/28/26.
//

import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let isRunningUITests: Bool
    let container: AppContainer

    var settingsViewModel: SettingsViewModel { container.settingsViewModel }
    var notchViewModel: NotchViewModel { container.notchViewModel }
    var notchEventCoordinator: NotchEventCoordinator { container.notchEventCoordinator }
    var hardwareHUDMonitor: HardwareHUDMonitor { container.hardwareHUDMonitor }
    var lockScreenPanelManager: LockScreenPanelManager { container.lockScreenPanelManager }
    var lockScreenLiveActivityWindowManager: LockScreenLiveActivityWindowManager { container.lockScreenLiveActivityWindowManager }
    var lockScreenFaceIDWindowManager: LockScreenFaceIDWindowManager { container.lockScreenFaceIDWindowManager }
    var airDropViewModel: AirDropNotchViewModel { container.airDropViewModel }
    var airDropController: NotchAirDropController { container.airDropController }
    var lockScreenManager: LockScreenManager { container.lockScreenManager }
    var nowPlayingViewModel: NowPlayingViewModel { container.nowPlayingViewModel }
    var downloadViewModel: DownloadViewModel { container.downloadViewModel }
    var timerViewModel: TimerViewModel { container.timerViewModel }
    var screenRecordingViewModel: ScreenRecordingViewModel { container.screenRecordingViewModel }
    var externalDrivesMonitor: ExternalDrivesMonitor { container.externalDrivesMonitor }
    var powerService: PowerService { container.powerService }
    var powerViewModel: PowerViewModel { container.powerViewModel }
    var bluetoothViewModel: BluetoothViewModel { container.bluetoothViewModel }
    var wifiViewModel: WifiViewModel { container.wifiViewModel }
    var vpnViewModel: VpnViewModel { container.vpnViewModel }
    var focusViewModel: FocusViewModel { container.focusViewModel }
    
    var window: OverlayPanelWindow!
    var localClickMonitor: Any?
    let globalClickMonitor = GlobalClickMonitor()
    var hideWindowWorkItem: DispatchWorkItem?
    var cancellables = Set<AnyCancellable>()
    var isPrimaryWindowSuspendedForLock = false
    var expansionTime: Date = .distantPast
    
    override init() {
        let isRunningUITests = AppEnvironment.isRunningUITests
        let isRunningTests = AppEnvironment.isRunningTests
        self.isRunningUITests = isRunningUITests
        self.container = AppContainer(isRunningTests: isRunningTests)
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningUnitTests else {
            // Running as test host for unit tests: do not start UI, windows, monitors, or permission prompts.
            return
        }
        if !isRunningUITests && !AppIdentity.prepareLaunch() { return }

        applyActivationPolicy(
            showsDockIcon: isRunningUITests || settingsViewModel.application.isDockIconVisible
        )
        observeDisplayLocationChanges()
        observeFullscreenVisibilityChanges()
        observeDockIconVisibilityChanges()
        observeHUDConfigurationChanges()
        observeFeatureMonitoringChanges()
        observeLockScreenWindowHandoff()
        
        SettingsWindowController.shared.setupDependencies(appDelegate: self)
        NotificationCenter.default.publisher(for: .init("notch.showWelcome"))
            .sink { [weak self] _ in
                guard let self else { return }
                WelcomeWindowController.shared.show(agents: self.container.aiAgentsViewModel)
            }
            .store(in: &cancellables)

        if !isRunningUITests {
            createNotchWindow()
            observeOutsideClickDismissal()
            _ = lockScreenPanelManager
            _ = lockScreenLiveActivityWindowManager
            _ = lockScreenFaceIDWindowManager
            hardwareHUDMonitor.startMonitoring()
            _ = container.aiAgentEventsHandler
            container.aiAgentsViewModel.start()
            container.notchlessWindowConstrainer.start()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateWindowFrame),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            observeWorkspaceChanges()

            DispatchQueue.main.async {
                for w in NSApp.windows {
                    if w !== self.window {
                        w.orderOut(nil)
                    }
                }
                if !UserDefaults.standard.bool(forKey: "welcome.seen") {
                    WelcomeWindowController.shared.show(agents: self.container.aiAgentsViewModel)
                }
            }
        }

        if !isRunningUITests {
            // The welcome window explains the app without occupying the live-activity surface.
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            SparkleUpdater.shared.$isUpdateAvailable
                .receive(on: RunLoop.main)
                .sink { [weak self] isAvailable in
                    self?.notchEventCoordinator.handleSoftwareUpdateEvent(isAvailable ? .updateAvailable : .upToDate)
                }
                .store(in: &cancellables)
        }

        lockScreenManager.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.aiAgentsViewModel.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        container.lockScreenManager.stopMonitoring()
        container.nowPlayingViewModel.stopMonitoring()
        container.downloadViewModel.stopMonitoring()
        container.timerViewModel.stopMonitoring()
        container.screenRecordingViewModel.stopMonitoring()
        container.hardwareHUDMonitor.stopMonitoring()
        container.notchlessWindowConstrainer.stop()
        if !isRunningUITests {
            container.lockScreenPanelManager.invalidate()
            container.lockScreenLiveActivityWindowManager.invalidate()
            container.lockScreenFaceIDWindowManager.invalidate()
        }
        stopOutsideClickMonitoring()
        hideWindowWorkItem?.cancel()
        hideWindowWorkItem = nil
        container.externalDrivesMonitor.stopMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Settings and the agent management scene are optional windows. Closing
        // either must not terminate this persistent menu-bar/overlay utility.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.showWindow()
        return true
    }

    func applyActivationPolicy(showsDockIcon: Bool) {
        let targetPolicy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory

        guard NSApp.activationPolicy() != targetPolicy else { return }

        NSApp.setActivationPolicy(targetPolicy)

        if showsDockIcon {
            NSApp.activate(ignoringOtherApps: false)
        }
    }
}
