import SwiftUI

struct EnvironmentSelectionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("어떤 환경에서 쓸 영어인가요?")
                        .font(.title.bold())
                    Text("상황에 맞는 실용적인 문장을 준비할게요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Environment cards
                VStack(spacing: 12) {
                    ForEach(LearningEnvironment.allCases) { env in
                        EnvironmentCard(
                            environment: env,
                            isSelected: viewModel.selectedEnvironment == env
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedEnvironment = env
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .readableContentWidth(600)
        }
        .scrollIndicators(.hidden)
    }
}

private struct EnvironmentCard: View {
    let environment: LearningEnvironment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(environment.emoji)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : Color(.tertiarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(environment.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
