import SwiftUI

struct ScenarioCardView: View {
    let scenario: Scenario
    let index: Int
    let lessonDate: String
    @State private var showTranslation = false
    @State private var selectedWord: String?

    @State private var vocabulary = VocabularyService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 시나리오 헤더
            HStack(alignment: .top, spacing: 10) {
                Text("\(index)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.titleKo)
                        .font(.headline)
                    Text(scenario.titleEn)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // 상황 설명
            Text(scenario.context)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            // 영어 문장 (탭 가능)
            TappableTextView(text: scenario.sentenceEn) { word in
                selectedWord = word
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.06))
            )

            // 한국어 번역 토글
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTranslation.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTranslation ? "eye.slash" : "eye")
                    Text(showTranslation ? "번역 숨기기" : "번역 보기")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
            }

            if showTranslation {
                Text(scenario.sentenceKo)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 문법 포인트
            VStack(alignment: .leading, spacing: 8) {
                Label("문법 포인트", systemImage: "pencil.and.list.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                ForEach(scenario.grammar) { point in
                    GrammarPointRow(point: point)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .sheet(isPresented: Binding(
            get: { selectedWord != nil },
            set: { if !$0 { selectedWord = nil } }
        )) {
            if let word = selectedWord {
                WordDetailSheet(
                    word: word,
                    sentence: scenario.sentenceEn,
                    lessonDate: lessonDate
                )
            }
        }
    }
}

// MARK: - 단어 상세 시트

private struct WordDetailSheet: View {
    let word: String
    let sentence: String
    let lessonDate: String
    @Environment(\.dismiss) private var dismiss

    @State private var vocabulary = VocabularyService.shared
    @State private var meaning: String?
    @State private var isLoadingMeaning = true
    private var isSaved: Bool { vocabulary.isSaved(word) }

    var body: some View {
        VStack(spacing: 16) {
            // 드래그 핸들
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // 단어
            Text(word)
                .font(.title.bold())

            // 뜻
            Group {
                if isLoadingMeaning {
                    ProgressView()
                        .frame(height: 40)
                } else if let meaning {
                    Text(meaning)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Text("뜻을 찾을 수 없습니다")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }

            // 문장 컨텍스트
            Text(highlightedSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            // 저장/삭제 버튼
            Button {
                if isSaved {
                    if let entry = vocabulary.words.first(where: {
                        $0.word.caseInsensitiveCompare(word) == .orderedSame
                    }) {
                        vocabulary.remove(id: entry.id)
                    }
                } else {
                    vocabulary.save(word, meaning: meaning, sentence: sentence, lessonDate: lessonDate)
                }
                dismiss()
            } label: {
                Label(
                    isSaved ? "단어장에서 삭제" : "단어장에 저장",
                    systemImage: isSaved ? "bookmark.slash.fill" : "bookmark.fill"
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSaved ? Color.red : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .task {
            meaning = await DictionaryService.shared.lookup(word)
            isLoadingMeaning = false
        }
    }

    private var highlightedSentence: AttributedString {
        var result = AttributedString(sentence)
        if let range = result.range(of: word, options: .caseInsensitive) {
            result[range].foregroundColor = .primary
            result[range].font = .caption.bold()
        }
        return result
    }
}

// MARK: - 문법 포인트

private struct GrammarPointRow: View {
    let point: GrammarPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(point.pattern)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.blue)

            Text(point.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let example = point.example, !example.isEmpty {
                Text("e.g. \(example)")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}
