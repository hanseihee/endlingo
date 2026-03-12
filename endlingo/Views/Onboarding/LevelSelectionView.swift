import SwiftUI

struct LevelSelectionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("영어 수준을 선택하세요")
                        .font(.title.bold())
                    Text("현재 실력에 맞는 문장을 보내드릴게요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                // Level cards
                VStack(spacing: 12) {
                    ForEach(EnglishLevel.allCases) { level in
                        LevelCard(
                            level: level,
                            isSelected: viewModel.selectedLevel == level
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedLevel = level
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LevelCard: View {
    let level: EnglishLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(level.emoji)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected
                            ? Color.blue.opacity(0.15)
                            : Color(.tertiarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
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
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
