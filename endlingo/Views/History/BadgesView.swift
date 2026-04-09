import SwiftUI

struct BadgesView: View {
    @State private var gamification = GamificationService.shared
    @State private var selectedBadge: BadgeType?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var earnedSet: Set<String> {
        Set(gamification.earnedBadges.map { $0.badgeType })
    }

    private var earnedCount: Int { gamification.earnedBadges.count }
    private var totalCount: Int { BadgeType.allCases.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 진행도
                VStack(spacing: 8) {
                    Text("\(earnedCount) / \(totalCount)")
                        .font(.title.bold())

                    ProgressView(value: Double(earnedCount), total: Double(totalCount))
                        .tint(.yellow)
                        .padding(.horizontal, 40)

                    Text("배지 획득률 \(totalCount > 0 ? earnedCount * 100 / totalCount : 0)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // 카테고리별 섹션
                ForEach(BadgeCategory.allCases, id: \.rawValue) { category in
                    let badges = BadgeType.allCases.filter { $0.category == category }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(category.title)
                                .font(.headline)

                            let catEarned = badges.filter { earnedSet.contains($0.rawValue) }.count
                            Text("\(catEarned)/\(badges.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(badges) { badge in
                                let isEarned = earnedSet.contains(badge.rawValue)
                                BadgeCard(badge: badge, isEarned: isEarned)
                                    .onTapGesture { selectedBadge = badge }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("배지")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(
                badge: badge,
                isEarned: earnedSet.contains(badge.rawValue),
                earnedDate: gamification.earnedBadges.first(where: { $0.badgeType == badge.rawValue })?.earnedAt
            )
            .presentationDetents([.medium])
        }
    }
}

// MARK: - 배지 상세 시트

private struct BadgeDetailSheet: View {
    let badge: BadgeType
    let isEarned: Bool
    let earnedDate: Date?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: badge.icon)
                .font(.system(size: 48))
                .foregroundStyle(isEarned ? badge.category.color : .gray.opacity(0.4))
                .padding(.top, 24)

            Text(badge.title)
                .font(.title2.bold())

            Text(badge.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if isEarned, let date = earnedDate {
                Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Label(String(localized: "아직 획득하지 못했습니다"), systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct BadgeCard: View {
    let badge: BadgeType
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.system(size: 28))
                .foregroundStyle(isEarned ? badge.category.color : .gray.opacity(0.3))

            Text(badge.title)
                .font(.caption2.bold())
                .foregroundStyle(isEarned ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isEarned ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEarned ? badge.category.color.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

}
