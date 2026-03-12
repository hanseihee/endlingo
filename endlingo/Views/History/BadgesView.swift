import SwiftUI

struct BadgesView: View {
    @State private var gamification = GamificationService.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var earnedSet: Set<String> {
        Set(gamification.earnedBadges.map { $0.badgeType })
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(BadgeType.allCases) { badge in
                    let isEarned = earnedSet.contains(badge.rawValue)
                    BadgeCard(badge: badge, isEarned: isEarned, earnedDate: earnedDate(for: badge))
                }
            }
            .padding(20)
        }
        .navigationTitle("배지")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private func earnedDate(for badge: BadgeType) -> Date? {
        gamification.earnedBadges.first { $0.badgeType == badge.rawValue }?.earnedAt
    }
}

private struct BadgeCard: View {
    let badge: BadgeType
    let isEarned: Bool
    let earnedDate: Date?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: badge.icon)
                .font(.system(size: 36))
                .foregroundStyle(isEarned ? badgeColor : .gray.opacity(0.4))

            Text(badge.title)
                .font(.callout.bold())
                .foregroundStyle(isEarned ? .primary : .secondary)

            Text(badge.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let date = earnedDate {
                Text(date, format: .dateTime.month().day())
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isEarned ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isEarned ? badgeColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

    private var badgeColor: Color {
        switch badge {
        case .firstStep: return .yellow
        case .wordCollector50, .wordCollector100: return .green
        case .sevenDayStreak, .thirtyDayStreak: return .orange
        case .quizMaster: return .purple
        case .quizEnthusiast: return .mint
        }
    }
}
