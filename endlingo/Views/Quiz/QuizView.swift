import SwiftUI

struct QuizView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = QuizViewModel()
    @State private var speech = SpeechService.shared
    @State private var selectedType: QuizType = .enToKo
    @State private var selectedSource: QuizWordSource = .builtin
    @State private var showMasteredList = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isFinished {
                    quizSummary
                } else if viewModel.questions.isEmpty {
                    quizSetup
                } else {
                    quizQuestion
                }
            }
            .navigationTitle("단어 퀴즈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        speech.stop()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showMasteredList) {
                MasteredWordsSheet(viewModel: viewModel)
            }
        }
    }

    private func speakFirstQuestion() {
        if let q = viewModel.questions.first, q.quizType == .enToKo {
            speech.speak(q.wordText, id: "quiz-0")
        }
    }

    // MARK: - 퀴즈 설정

    private var quizSetup: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("단어 퀴즈")
                .font(.title2.bold())

            // 단어 소스 선택
            VStack(spacing: 12) {
                Text("단어 범위")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("범위", selection: $selectedSource) {
                    ForEach(QuizWordSource.allCases, id: \.rawValue) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }

            if !viewModel.canStartQuiz(source: selectedSource) {
                Text("단어를 5개 이상 저장해야\n퀴즈를 시작할 수 있습니다")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                // 퀴즈 유형 선택
                VStack(spacing: 12) {
                    Text("퀴즈 유형")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("유형", selection: $selectedType) {
                        Text("영어 → 한국어").tag(QuizType.enToKo)
                        Text("한국어 → 영어").tag(QuizType.koToEn)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                }

                sourceDescription

                if viewModel.masteredCount > 0 {
                    Text("외운 단어 \(viewModel.masteredCount)개 제외")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Button {
                        showMasteredList = true
                    } label: {
                        Text("외운 단어 관리")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            if viewModel.canStartQuiz(source: selectedSource) {
                Button {
                    viewModel.generateQuiz(type: selectedType, source: selectedSource)
                    speakFirstQuestion()
                } label: {
                    Text("시작하기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var sourceDescription: some View {
        Group {
            switch selectedSource {
            case .saved:
                let count = VocabularyService.shared.words.filter { $0.meaning != nil }.count
                Text("저장된 단어 \(count)개에서 출제됩니다")
            case .builtin:
                let count = BuiltInWordBank.shared.words.count
                Text("필수 영단어 \(count)개에서 출제됩니다")
            case .mixed:
                let saved = VocabularyService.shared.words.filter { $0.meaning != nil }.count
                let builtin = BuiltInWordBank.shared.words.count
                Text("전체 \(saved + builtin)개 단어에서 출제됩니다")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - 문제

    private var quizQuestion: some View {
        VStack(spacing: 24) {
            // 프로그레스
            HStack {
                Text("\(viewModel.currentIndex + 1) / \(viewModel.questions.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("+\(viewModel.totalXPEarned) XP")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 24)

            ProgressView(value: viewModel.progress)
                .tint(.orange)
                .padding(.horizontal, 24)

            Spacer()

            if let question = viewModel.currentQuestion {
                // 질문
                VStack(spacing: 8) {
                    Text(question.quizType == .enToKo ? "이 단어의 뜻은?" : "이 뜻의 영어 단어는?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(question.quizType == .enToKo ? question.wordText : question.meaningText)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        if question.quizType == .enToKo {
                            SpeakButton(
                                text: question.wordText,
                                id: "quiz-\(viewModel.currentIndex)",
                                font: .body,
                                color: .orange
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .onChange(of: viewModel.currentIndex) { _, _ in
                    if let q = viewModel.currentQuestion, q.quizType == .enToKo {
                        speech.speak(q.wordText, id: "quiz-\(viewModel.currentIndex)")
                    }
                }

                Spacer()

                // 선택지
                VStack(spacing: 10) {
                    ForEach(0..<question.options.count, id: \.self) { index in
                        OptionButton(
                            text: question.options[index],
                            index: index,
                            isSelected: viewModel.selectedAnswer == index,
                            isCorrect: index == question.correctIndex,
                            isAnswered: viewModel.isAnswered
                        ) {
                            viewModel.selectAnswer(index)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // 외웠어요 버튼 + 다음 버튼
                if viewModel.isAnswered {
                    VStack(spacing: 8) {
                        // 정답일 때 외웠어요 토글
                        if viewModel.selectedAnswer == question.correctIndex {
                            let mastered = viewModel.isMastered(question.wordText)
                            Button {
                                viewModel.toggleMastered(question.wordText)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mastered ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(mastered ? .green : .secondary)
                                    Text(mastered ? "외운 단어에서 해제" : "외웠어요")
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(mastered ? .green : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            viewModel.nextQuestion()
                        } label: {
                            Text(viewModel.currentIndex + 1 >= viewModel.questions.count ? "결과 보기" : "다음 문제")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 16)
        }
    }

    // MARK: - 결과 요약

    private var quizSummary: some View {
        VStack(spacing: 24) {
            Spacer()

            // 점수
            let total = viewModel.questions.count
            let correct = viewModel.correctCount
            let accuracy = total > 0 ? Int(Double(correct) / Double(total) * 100) : 0

            Image(systemName: accuracy >= 80 ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accuracy >= 80 ? .yellow : .green)

            Text(accuracy >= 80 ? "훌륭합니다!" : "수고했습니다!")
                .font(.title2.bold())

            VStack(spacing: 8) {
                HStack(spacing: 24) {
                    SummaryItem(label: "정답", value: "\(correct)/\(total)")
                    SummaryItem(label: "정답률", value: "\(accuracy)%")
                    SummaryItem(label: "획득 XP", value: "+\(viewModel.totalXPEarned)")
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    viewModel.generateQuiz(type: selectedType, source: selectedSource)
                    speakFirstQuestion()
                } label: {
                    Text("다시 도전하기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    dismiss()
                } label: {
                    Text("돌아가기")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Components

private struct OptionButton: View {
    let text: String
    let index: Int
    let isSelected: Bool
    let isCorrect: Bool
    let isAnswered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isAnswered {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
        .disabled(isAnswered)
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        if !isAnswered { return .primary }
        if isCorrect { return .green }
        if isSelected { return .red }
        return .secondary
    }

    private var backgroundColor: Color {
        if !isAnswered { return Color(.tertiarySystemGroupedBackground) }
        if isCorrect { return Color.green.opacity(0.08) }
        if isSelected { return Color.red.opacity(0.08) }
        return Color(.tertiarySystemGroupedBackground)
    }

    private var borderColor: Color {
        if !isAnswered { return Color.clear }
        if isCorrect { return Color.green.opacity(0.4) }
        if isSelected { return Color.red.opacity(0.4) }
        return Color.clear
    }
}

private struct SummaryItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 외운 단어 관리

private struct MasteredWordsSheet: View {
    @Bindable var viewModel: QuizViewModel
    @Environment(\.dismiss) private var dismiss

    private var sortedWords: [String] {
        viewModel.masteredWords.sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedWords.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("외운 단어가 없습니다")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(sortedWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(.body)

                                Spacer()

                                Button {
                                    viewModel.toggleMastered(word)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("외운 단어 (\(sortedWords.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
