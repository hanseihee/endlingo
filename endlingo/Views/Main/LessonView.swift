import SwiftUI

struct LessonView: View {
    @State private var viewModel = LessonViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                datePicker

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
                .frame(maxHeight: .infinity)
            }
            .navigationTitle(viewModel.isToday ? String(localized: "오늘의 레슨") : String(localized: "지난 레슨"))
        }
        .task {
            await viewModel.loadTodayLesson()
            if viewModel.isToday, let lesson = viewModel.lesson {
                recordLesson(lesson)
            }
        }
    }

    // MARK: - 날짜 선택

    private var datePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.availableDates, id: \.self) { date in
                        let isSelected = viewModel.dateString(for: date) == viewModel.dateString(for: viewModel.selectedDate)

                        Button {
                            viewModel.selectDate(date)
                        } label: {
                            VStack(spacing: 4) {
                                Text(viewModel.weekdayLabel(for: date))
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? .white : .secondary)

                                Text(viewModel.dayLabel(for: date))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .id(viewModel.dateString(for: date))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo(viewModel.dateString(for: viewModel.selectedDate), anchor: .trailing)
            }
        }
        .background(Color(.systemBackground))
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
            LessonService.shared.clearCache()
            await viewModel.loadLesson()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("레슨을 불러오는 중...")
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
                Task { await viewModel.loadLesson() }
            } label: {
                Text("다시 시도")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
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
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
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
