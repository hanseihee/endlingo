import SwiftUI

struct StatsSummaryCard: View {
    let stats: UserStats

    var body: some View {
        VStack(spacing: 16) {
            // 레벨 + XP 프로그레스
            HStack(spacing: 12) {
                // 레벨 뱃지
                Text("Lv.\(stats.userLevel)")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(levelGradient)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(stats.levelTitle)
                        .font(.headline)

                    ProgressView(value: stats.xpProgress)
                        .tint(.blue)

                    Text("\(stats.totalXP) / \(stats.xpForNextLevel) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 통계 그리드
            LazyVGrid(columns: [.init(), .init(), .init()], spacing: 12) {
                StatItem(icon: "flame.fill", value: "\(stats.currentStreak)" + String(localized: "일"), label: String(localized: "연속 학습"), color: .orange)
                StatItem(icon: "trophy.fill", value: "\(stats.bestStreak)" + String(localized: "일"), label: String(localized: "최장 기록"), color: .yellow)
                StatItem(icon: "calendar", value: "\(stats.totalLearningDays)" + String(localized: "일"), label: String(localized: "총 학습일"), color: .blue)
                StatItem(icon: "character.book.closed.fill", value: "\(VocabularyService.shared.words.count)", label: String(localized: "저장 단어"), color: .green)
                StatItem(icon: "checkmark.circle.fill", value: "\(stats.totalQuizzes)", label: String(localized: "퀴즈 횟수"), color: .purple)
                StatItem(
                    icon: "percent",
                    value: stats.totalQuizzes > 0 ? String(format: "%.0f%%", stats.quizAccuracy) : "-",
                    label: String(localized: "정답률"),
                    color: .mint
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var levelGradient: LinearGradient {
        switch stats.userLevel {
        case 1...5:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 6...10:
            return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 11...20:
            return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.callout.bold())

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
