import SwiftUI

struct OnboardingContainerView: View {
    @State private var viewModel = OnboardingViewModel()
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: viewModel.progress)
                .tint(.blue)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.3), value: viewModel.progress)

            // Content
            TabView(selection: $viewModel.currentStep) {
                LevelSelectionView(viewModel: viewModel)
                    .tag(OnboardingStep.level)

                EnvironmentSelectionView(viewModel: viewModel)
                    .tag(OnboardingStep.environment)

                TimePickerView(viewModel: viewModel)
                    .tag(OnboardingStep.time)

                OnboardingCompleteView(viewModel: viewModel) {
                    viewModel.completeOnboarding()
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                }
                .tag(OnboardingStep.complete)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

            // Bottom buttons
            if viewModel.currentStep != .complete {
                bottomButtons
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var bottomButtons: some View {
        HStack(spacing: 16) {
            if viewModel.currentStep != .level {
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
