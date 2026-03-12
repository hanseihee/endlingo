import SwiftUI

struct HistoryView: View {
    @State private var gamification = GamificationService.shared
    @State private var showQuiz = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 통계 요약
                    StatsSummaryCard(stats: gamification.stats)
                        .padding(.horizontal, 16)

                    // 학습 캘린더
                    LearningCalendarView()
                        .padding(.horizontal, 16)

                    // 퀵 액션
                    VStack(spacing: 12) {
                        // 퀴즈 버튼
                        Button {
                            showQuiz = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "brain.head.profile.fill")
                                    .font(.title3)
                                    .foregroundStyle(.purple)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("단어 퀴즈")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("저장한 단어로 실력을 테스트하세요")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)

                        // 배지 버튼
                        NavigationLink {
                            BadgesView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trophy.fill")
                                    .font(.title3)
                                    .foregroundStyle(.yellow)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("배지")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    let earned = gamification.earnedBadges.count
                                    let total = BadgeType.allCases.count
                                    Text("\(earned)/\(total)개 획득")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("기록")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showQuiz) {
                QuizView()
            }
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
