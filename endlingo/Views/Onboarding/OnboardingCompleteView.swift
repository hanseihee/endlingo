import SwiftUI

struct OnboardingCompleteView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Celebration
            VStack(spacing: 16) {
                Text("🎉")
                    .font(.system(size: 64))

                Text("준비 완료!")
                    .font(.largeTitle.bold())

                Text("매일 새로운 영어 문장으로\n실력을 키워보세요")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Summary
            VStack(spacing: 12) {
                if let level = viewModel.selectedLevel {
                    SummaryRow(icon: level.emoji, label: String(localized: "레벨"), value: level.title)
                }
                if let env = viewModel.selectedEnvironment {
                    SummaryRow(icon: env.emoji, label: String(localized: "환경"), value: env.title)
                }
                SummaryRow(
                    icon: "⏰",
                    label: String(localized: "알림"),
                    value: String(format: String(localized: "매일 %d:%02d"), viewModel.selectedHour, viewModel.selectedMinute)
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            Spacer()

            // Start button
            Button(action: onStart) {
                Text("시작하기")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }
}

private struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(icon)
                .font(.title3)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
        }
    }
}
