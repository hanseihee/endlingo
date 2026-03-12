import SwiftUI

struct HistoryView: View {
    @State private var gamification = GamificationService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 통계 요약
                    StatsSummaryCard(stats: gamification.stats)
                        .padding(.horizontal, 16)

                    // 주간 비교
                    WeekComparisonCard()
                        .padding(.horizontal, 16)

                    // 학습 캘린더
                    LearningCalendarView()
                        .padding(.horizontal, 16)

                    // 최근 활동
                    RecentActivityCard()
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("기록")
            .background(Color(.systemGroupedBackground))
            .overlay {
                // 배지 획득 알림
                if let badge = gamification.newBadge {
                    badgeToast(badge)
                }
            }
        }
    }

    private func badgeToast(_ badge: BadgeType) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: badge.icon)
                    .font(.title3)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("배지 획득!")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(badge.title)
                        .font(.callout.bold())
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .shadow(radius: 8)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture {
                withAnimation { gamification.dismissNewBadge() }
            }
            .task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { gamification.dismissNewBadge() }
            }
        }
        .animation(.spring, value: gamification.newBadge == nil)
    }
}
