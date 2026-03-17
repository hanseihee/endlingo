import SwiftUI

struct WeekComparisonCard: View {
    @State private var gamification = GamificationService.shared

    private var thisWeek: GamificationService.WeekStats {
        gamification.weekStats(for: gamification.thisWeekStart)
    }

    private var lastWeek: GamificationService.WeekStats {
        gamification.weekStats(for: gamification.lastWeekStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("주간 비교")
                .font(.headline)

            HStack(spacing: 0) {
                Text("이번 주")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                Text("")
                    .frame(width: 80)
                Text("지난 주")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ComparisonRow(
                label: String(localized: "학습일"),
                thisValue: "\(thisWeek.learningDays)" + String(localized: "일"),
                lastValue: "\(lastWeek.learningDays)" + String(localized: "일"),
                diff: thisWeek.learningDays - lastWeek.learningDays
            )

            ComparisonRow(
                label: String(localized: "획득 XP"),
                thisValue: "\(thisWeek.totalXP)",
                lastValue: "\(lastWeek.totalXP)",
                diff: thisWeek.totalXP - lastWeek.totalXP
            )

            ComparisonRow(
                label: String(localized: "퀴즈"),
                thisValue: "\(thisWeek.quizCount)" + String(localized: "회"),
                lastValue: "\(lastWeek.quizCount)" + String(localized: "회"),
                diff: thisWeek.quizCount - lastWeek.quizCount
            )

            ComparisonRow(
                label: String(localized: "정답률"),
                thisValue: thisWeek.quizCount > 0 ? String(format: "%.0f%%", thisWeek.quizAccuracy) : "-",
                lastValue: lastWeek.quizCount > 0 ? String(format: "%.0f%%", lastWeek.quizAccuracy) : "-",
                diff: thisWeek.quizCount > 0 && lastWeek.quizCount > 0
                    ? Int(thisWeek.quizAccuracy - lastWeek.quizAccuracy) : nil
            )

            ComparisonRow(
                label: String(localized: "저장 단어"),
                thisValue: "\(thisWeek.wordsSaved)" + String(localized: "개"),
                lastValue: "\(lastWeek.wordsSaved)" + String(localized: "개"),
                diff: thisWeek.wordsSaved - lastWeek.wordsSaved
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct ComparisonRow: View {
    let label: String
    let thisValue: String
    let lastValue: String
    let diff: Int?

    var body: some View {
        HStack(spacing: 0) {
            Text(thisValue)
                .font(.callout.bold())
                .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let diff, diff != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(abs(diff))")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(diff > 0 ? .green : .red)
                }
            }
            .frame(width: 80)

            Text(lastValue)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
