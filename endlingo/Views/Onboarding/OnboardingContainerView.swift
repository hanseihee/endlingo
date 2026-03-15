import SwiftUI

struct OnboardingContainerView: View {
    @State private var viewModel = OnboardingViewModel()
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar (로그인 화면에서는 숨김)
            if viewModel.currentStep != .login {
                ProgressView(value: viewModel.progress)
                    .tint(.blue)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
            }

            // Content
            Group {
                switch viewModel.currentStep {
                case .login:
                    LoginView(
                        onLoginSuccess: { viewModel.proceedAfterLogin() },
                        onGuestLogin: { viewModel.proceedAfterLogin() }
                    )
                case .level:
                    LevelSelectionView(viewModel: viewModel)
                case .environment:
                    EnvironmentSelectionView(viewModel: viewModel)
                case .time:
                    TimePickerView(viewModel: viewModel)
                case .complete:
                    OnboardingCompleteView(viewModel: viewModel) {
                        viewModel.completeOnboarding()
                        withAnimation { hasCompletedOnboarding = true }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

            // Bottom buttons (로그인/완료 화면에서는 숨김)
            if viewModel.currentStep != .login && viewModel.currentStep != .complete {
                bottomButtons
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var bottomButtons: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.back()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("이전")
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                viewModel.next()
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.currentStep == .time ? "완료" : "다음")
                    Image(systemName: "chevron.right")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(viewModel.canProceed ? Color.blue : Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!viewModel.canProceed)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}
