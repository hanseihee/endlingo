import SwiftUI

enum ActiveQuiz: Identifiable {
    case word, grammar, pronunciation, sentenceArrange
    var id: Self { self }
}

struct QuizTabView: View {
    @State private var activeQuiz: ActiveQuiz?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        quizCard(
                            image: "quiz-word",
                            title: String(localized: "단어 퀴즈"),
                            subtitle: String(localized: "영단어 실력을 테스트하세요")
                        ) {
                            activeQuiz = .word
                        }

                        quizCard(
                            image: "quiz-pronunciation",
                            title: String(localized: "발음 퀴즈"),
                            subtitle: String(localized: "단어를 소리 내어 읽어보세요")
                        ) {
                            activeQuiz = .pronunciation
                        }

                        quizCard(
                            image: "quiz-grammar",
                            title: String(localized: "문법 퀴즈"),
                            subtitle: String(localized: "문법 실력을 테스트하세요")
                        ) {
                            activeQuiz = .grammar
                        }

                        quizCard(
                            image: "quiz-sentence",
                            title: String(localized: "문장 배열"),
                            subtitle: String(localized: "단어를 올바른 순서로 배열하세요")
                        ) {
                            activeQuiz = .sentenceArrange
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .readableContentWidth()
                }

                BannerAdView()
                    .padding(.bottom, 4)
            }
            .navigationTitle("퀴즈")
            .sheet(item: $activeQuiz) { quiz in
                switch quiz {
                case .word: QuizView()
                case .grammar: GrammarQuizView()
                case .pronunciation: PronunciationQuizView()
                case .sentenceArrange: SentenceArrangeQuizView()
                }
            }
        }
    }

    private func quizCard(image: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
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
}
