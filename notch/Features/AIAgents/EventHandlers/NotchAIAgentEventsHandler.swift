import Combine
import Foundation

@MainActor
final class NotchAIAgentEventsHandler {
    private var cancellables = Set<AnyCancellable>()
    private var displayedSignature: String?

    init(viewModel: AIAgentsViewModel, notch: NotchViewModel, lockScreen: LockScreenManager) {
        Publishers.CombineLatest4(
            viewModel.$sessions, viewModel.$enabled, viewModel.$showCompletions,
            Publishers.CombineLatest3(lockScreen.$isLocked, lockScreen.$isPreparingLock, lockScreen.$isLockIdle)
                .map { $0 || $1 || !$2 }
        )
        // @Published emits before assignment; render after all stored values are current.
        .receive(on: RunLoop.main)
        .sink { [weak self, weak viewModel, weak notch] _, enabled, _, isLocked in
            guard let self, let viewModel, let notch else { return }
            let visible = viewModel.visibleSessions
            let signature = enabled && !isLocked && !visible.isEmpty
                ? visible.map { "\($0.id):\($0.status.rawValue)" }.joined(separator: "|") : nil
            guard signature != self.displayedSignature else { return }
            self.displayedSignature = signature
            if signature != nil {
                notch.send(.showLiveActivity(AIAgentNotchContent(viewModel: viewModel)))
            } else {
                notch.send(.hideLiveActivity(id: NotchContentRegistry.AIAgents.active.id))
            }
        }
        .store(in: &cancellables)
    }
}
