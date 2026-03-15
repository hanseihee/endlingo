import SwiftUI

struct BadgesView: View {
    @State private var gamification = GamificationService.shared

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
    }
}

private struct BadgeCard: View {
    let badge: BadgeType
    let isEarned: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: badge.icon)
                .font(.system(size: 28))
                .foregroundStyle(isEarned ? badgeColor : .gray.opacity(0.3))

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
                .stroke(isEarned ? badgeColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

    private var badgeColor: Color {
        switch badge.category {
        case .learning: return .blue
        case .vocabulary: return .green
        case .streak: return .orange
        case .quiz: return .purple
        case .level: return .mint
        }
    }
}
