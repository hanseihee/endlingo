import SwiftUI

struct QuizView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = QuizViewModel()
    @State private var selectedType: QuizType = .enToKo

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
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: - 퀴즈 설정

    private var quizSetup: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 56))
                .foregroundStyle(.purple)

            Text("단어 퀴즈")
                .font(.title2.bold())

            if !viewModel.canStartQuiz {
                Text("단어를 4개 이상 저장해야\n퀴즈를 시작할 수 있습니다")
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
                    .padding(.horizontal, 40)
                }

                Text("저장된 단어에서 최대 10문제가 출제됩니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if viewModel.canStartQuiz {
                Button {
                    viewModel.generateQuiz(type: selectedType)
                } label: {
                    Text("시작하기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
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
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 24)

            ProgressView(value: viewModel.progress)
                .tint(.purple)
                .padding(.horizontal, 24)

            Spacer()

            if let question = viewModel.currentQuestion {
                // 질문
                VStack(spacing: 8) {
                    Text(question.quizType == .enToKo ? "이 단어의 뜻은?" : "이 뜻의 영어 단어는?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(question.quizType == .enToKo ? question.word.word : (question.word.meaning ?? ""))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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

                // 다음 버튼
                if viewModel.isAnswered {
                    Button {
                        viewModel.nextQuestion()
                    } label: {
                        Text(viewModel.currentIndex + 1 >= viewModel.questions.count ? "결과 보기" : "다음 문제")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    viewModel.generateQuiz(type: selectedType)
                } label: {
                    Text("다시 도전하기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.purple)
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
