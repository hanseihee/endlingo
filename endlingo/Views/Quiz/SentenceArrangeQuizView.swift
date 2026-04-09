import SwiftUI

struct SentenceArrangeQuizView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SentenceArrangeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    quizContent
                }
            }
            .navigationTitle("문장 배열")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Text("\(viewModel.correctCount)/\(viewModel.totalCount)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        if viewModel.totalXPEarned > 0 {
                            Text("+\(viewModel.totalXPEarned) XP")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            await viewModel.loadSentences()
        }
    }

    // MARK: - 로딩

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("문장을 불러오는 중...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 에러

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("닫기") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 퀴즈 콘텐츠

    private var quizContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // 한국어 힌트
                    Text(viewModel.currentSentenceKo)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // 답 영역
                    answerArea
                        .padding(.horizontal, 16)

                    // 구분선
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                        .padding(.horizontal, 32)

                    // 선택지 영역
                    selectionArea
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }

            // 하단 버튼
            bottomButton
        }
    }

    // MARK: - 답 영역

    private var answerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("영어 문장을 완성하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)

            FlowLayout(spacing: 8) {
                ForEach(viewModel.placedWords) { word in
                    WordChip(
                        text: word.text,
                        style: chipStyle(for: word),
                        isLocked: viewModel.isChecked,
                        action: { withAnimation(.snappy(duration: 0.25)) { viewModel.deselectWord(word) } }
                    )
                }

                // 빈 슬롯 표시
                ForEach(0..<viewModel.shuffledWords.count, id: \.self) { _ in
                    Text("     ")
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - 선택지 영역

    private var selectionArea: some View {
        FlowLayout(spacing: 8) {
            ForEach(viewModel.shuffledWords) { word in
                WordChip(
                    text: word.text,
                    style: .available,
                    action: { withAnimation(.snappy(duration: 0.25)) { viewModel.selectWord(word) } }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 하단 버튼

    private var bottomButton: some View {
        VStack(spacing: 0) {
            // 피드백 메시지
            if viewModel.isChecked {
                HStack {
                    Image(systemName: viewModel.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(viewModel.isCorrect ? String(localized: "정답입니다!") : String(localized: "다시 시도해보세요"))
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(viewModel.isCorrect ? .green : .red)
                .padding(.vertical, 8)

                // 오답 시 정답 표시
                if !viewModel.isCorrect {
                    Text(viewModel.correctWords.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            }

            // 버튼
            if viewModel.isChecked {
                if viewModel.isCorrect {
                    Button {
                        withAnimation { viewModel.nextSentence() }
                    } label: {
                        Text("다음 문장")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation { viewModel.retry() }
                        } label: {
                            Text("다시 시도")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            withAnimation { viewModel.skip() }
                        } label: {
                            Text("건너뛰기")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                Button {
                    withAnimation { viewModel.checkAnswer() }
                } label: {
                    Text("확인")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(viewModel.canCheck ? Color.accentColor : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.canCheck)
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - 칩 스타일 (실시간 피드백)

    private func chipStyle(for word: ArrangeWord) -> WordChipStyle {
        guard let index = viewModel.placedWords.firstIndex(where: { $0.id == word.id }) else {
            return .placed
        }

        // 채점 완료 + 전체 정답
        if viewModel.isChecked && viewModel.isCorrect {
            return .correct
        }

        // 해당 위치의 정답과 비교 (실시간)
        let isPositionCorrect = index < viewModel.correctWords.count
            && viewModel.placedWords[index].text == viewModel.correctWords[index]

        if viewModel.isChecked {
            return isPositionCorrect ? .correct : .wrong
        }

        // 배치 중: 맞는 위치 → 파란색, 틀린 위치 → 빨간색
        return isPositionCorrect ? .placed : .wrong
    }
}

// MARK: - WordChip

enum WordChipStyle {
    case available, placed, correct, wrong
}

private struct WordChip: View {
    let text: String
    let style: WordChipStyle
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.body.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(background)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private var background: some ShapeStyle {
        switch style {
        case .available:
            AnyShapeStyle(Color(.tertiarySystemGroupedBackground))
        case .placed:
            AnyShapeStyle(Color.accentColor.opacity(0.15))
        case .correct:
            AnyShapeStyle(Color.green.opacity(0.2))
        case .wrong:
            AnyShapeStyle(Color.red.opacity(0.2))
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .available: .primary
        case .placed: .accentColor
        case .correct: .green
        case .wrong: .red
        }
    }
}
