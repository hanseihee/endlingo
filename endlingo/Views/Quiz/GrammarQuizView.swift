import SwiftUI

struct GrammarQuizView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GrammarQuizViewModel()
    @State private var selectedType: GrammarQuizType = .patternToExplanation
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
            .navigationTitle("문법 퀴즈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showMasteredList) {
                MasteredGrammarSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - 퀴즈 설정

    private var quizSetup: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("quiz-grammar")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            Text("문법 퀴즈")
                .font(.title2.bold())

            if !viewModel.canStartQuiz() {
                Text("문법을 4개 이상 저장해야\n퀴즈를 시작할 수 있습니다")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("현재 저장된 문법: \(GrammarService.shared.grammars.count)개")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 12) {
                    Text("퀴즈 유형")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("유형", selection: $selectedType) {
                        Text("패턴 → 설명").tag(GrammarQuizType.patternToExplanation)
                        Text("설명 → 패턴").tag(GrammarQuizType.explanationToPattern)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                }

                Text("저장된 문법 \(viewModel.availableCount)개에서 출제됩니다")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if viewModel.masteredCount > 0 {
                    Text("외운 문법 \(viewModel.masteredCount)개 제외")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Button {
                        showMasteredList = true
                    } label: {
                        Text("외운 문법 관리")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Spacer()

            if viewModel.canStartQuiz() {
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
                VStack(spacing: 8) {
                    Text(question.quizType == .patternToExplanation
                         ? String(localized: "이 문법의 설명은?") : String(localized: "이 설명에 해당하는 문법은?"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(question.quizType == .patternToExplanation
                         ? question.pattern : question.explanation)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let example = question.example,
                       !example.isEmpty,
                       question.quizType == .patternToExplanation {
                        Text("e.g. \(example)")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 선택지
                VStack(spacing: 10) {
                    ForEach(0..<question.options.count, id: \.self) { index in
                        GrammarOptionButton(
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

                // 외웠어요 + 다음 버튼
                if viewModel.isAnswered {
                    VStack(spacing: 8) {
                        if viewModel.selectedAnswer == question.correctIndex {
                            let mastered = viewModel.isMastered(question.pattern)
                            Button {
                                viewModel.toggleMastered(question.pattern)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mastered ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(mastered ? .green : .secondary)
                                    Text(mastered ? String(localized: "외운 문법에서 해제") : String(localized: "외웠어요"))
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(mastered ? .green : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            viewModel.nextQuestion()
                        } label: {
                            Text(viewModel.currentIndex + 1 >= viewModel.questions.count ? String(localized: "결과 보기") : String(localized: "다음 문제"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.purple)
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

            let total = viewModel.questions.count
            let correct = viewModel.correctCount
            let accuracy = total > 0 ? Int(Double(correct) / Double(total) * 100) : 0

            Image(systemName: accuracy >= 80 ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accuracy >= 80 ? .yellow : .green)

            Text(accuracy >= 80 ? String(localized: "훌륭합니다!") : String(localized: "수고했습니다!"))
                .font(.title2.bold())

            VStack(spacing: 8) {
                HStack(spacing: 24) {
                    GrammarSummaryItem(label: String(localized: "정답"), value: "\(correct)/\(total)")
                    GrammarSummaryItem(label: String(localized: "정답률"), value: "\(accuracy)%")
                    GrammarSummaryItem(label: String(localized: "획득 XP"), value: "+\(viewModel.totalXPEarned)")
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

private struct GrammarOptionButton: View {
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

private struct GrammarSummaryItem: View {
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

// MARK: - 외운 문법 관리

private struct MasteredGrammarSheet: View {
    @Bindable var viewModel: GrammarQuizViewModel
    @Environment(\.dismiss) private var dismiss

    private var sortedGrammar: [String] {
        viewModel.masteredGrammar.sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedGrammar.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("외운 문법이 없습니다")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(sortedGrammar, id: \.self) { pattern in
                            HStack {
                                Text(pattern)
                                    .font(.body)

                                Spacer()

                                Button {
                                    viewModel.toggleMastered(pattern)
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
            .navigationTitle("외운 문법 (\(sortedGrammar.count))")
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
