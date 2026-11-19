//
//  LockScreenLiveActivityOverlayView.swift
//  notch
//
//  Created by Евгений Петрукович on 8/18/26.
//

import SwiftUI

struct LockScreenNotchOverlayView: View {
    @ObservedObject var notchViewModel: NotchViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var animator: LockScreenLiveActivityAnimator
    
    var body: some View {
        NotchInteractiveBodyView(
            notchViewModel: notchViewModel,
            settingsViewModel: settingsViewModel
        )
        // Defense in depth: even an outgoing animated agent view must render no metadata here.
        .environment(\.showsAIAgentContent, false)
        .environment(\.notchScale, notchViewModel.notchModel.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
