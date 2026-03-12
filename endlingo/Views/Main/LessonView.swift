import SwiftUI

struct LessonView: View {
    @State private var viewModel = LessonViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let lesson = viewModel.lesson {
                    lessonContent(lesson)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    loadingView
                }
            }
            .navigationTitle("오늘의 레슨")
        }
        .task {
            await viewModel.loadTodayLesson()
            if let lesson = viewModel.lesson {
                recordLesson(lesson)
            }
        }
    }

    private func recordLesson(_ lesson: DailyLesson) {
        GamificationService.shared.recordLessonView(
            level: lesson.level,
            environment: lesson.environment
        )
    }

    private func lessonContent(_ lesson: DailyLesson) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 테마 헤더
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.themeKo)
                        .font(.title2.bold())
                    Text(lesson.themeEn)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        LevelBadge(level: lesson.level)
                        EnvironmentBadge(environment: lesson.environment)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 시나리오 카드들
                ForEach(lesson.scenarios) { scenario in
                    ScenarioCardView(scenario: scenario, index: scenario.order, lessonDate: lesson.date)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.loadTodayLesson()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("오늘의 레슨을 불러오는 중...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.loadTodayLesson() }
            } label: {
                Text("다시 시도")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
    }
}

private struct LevelBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.caption.bold())
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct EnvironmentBadge: View {
    let environment: String

    private var displayName: String {
        LearningEnvironment(rawValue: environment)?.title ?? environment
    }

    private var emoji: String {
        LearningEnvironment(rawValue: environment)?.emoji ?? ""
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(emoji)
                .font(.caption2)
            Text(displayName)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}
