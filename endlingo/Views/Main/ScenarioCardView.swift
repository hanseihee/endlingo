import SwiftUI

struct ScenarioCardView: View {
    let scenario: Scenario
    let index: Int
    let lessonDate: String
    @State private var showTranslation = false
    @State private var selectedWord: String?

    @State private var showPronunciation = false
    @State private var pronunciationScore: Int?
    @State private var vocabulary = VocabularyService.shared

    @State private var grammarService = GrammarService.shared
    @State private var speech = SpeechService.shared

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
            TappableTextView(
                text: scenario.sentenceEn,
                highlightRange: speech.isSpeaking(id: "scenario-\(index)") ? speech.currentWordRange : nil
            ) { word in
                selectedWord = word
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.06))
            )

            // 따라 읽기 + 듣기 버튼
            HStack {
                Button {
                    showPronunciation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                        Text("따라 읽기")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Color.green)
                    )
                }

                if let score = pronunciationScore {
                    Button {
                        showPronunciation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("\(score)점")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(pronunciationGradeColor(score))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(pronunciationGradeColor(score).opacity(0.12))
                        )
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTranslation.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showTranslation ? "eye.slash" : "eye")
                        Text(showTranslation ? String(localized: "번역 숨기기") : String(localized: "번역 보기"))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                }

                SpeakButton(text: scenario.sentenceEn, id: "scenario-\(index)")
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
                    GrammarPointRow(
                        point: point,
                        isSaved: grammarService.isSaved(point.pattern),
                        onSave: {
                            grammarService.save(
                                pattern: point.pattern,
                                explanation: point.explanation,
                                example: point.example,
                                sentence: scenario.sentenceEn,
                                lessonDate: lessonDate
                            )
                        }
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onAppear {
            pronunciationScore = PronunciationScoreStore.load(date: lessonDate, index: index)
        }
        .onDisappear {
            speech.stop()
        }
        .sheet(isPresented: $showPronunciation) {
            PronunciationPracticeView(
                sentence: scenario.sentenceEn,
                scenarioTitle: scenario.titleEn,
                onScore: { score in
                    pronunciationScore = score
                    PronunciationScoreStore.save(score: score, date: lessonDate, index: index)
                }
            )
        }
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

    private func pronunciationGradeColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 70..<90: return .blue
        case 50..<70: return .orange
        default: return .red
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
    @State private var meanings: [WordMeaning] = []
    @State private var selected: Set<UUID> = []
    @State private var isLoading = true
    private var isSaved: Bool { vocabulary.isSaved(word) }

    private var selectedText: String? {
        WordMeaning.formatSelected(from: meanings, selected: selected)
    }

    var body: some View {
        VStack(spacing: 12) {
            // 드래그 핸들
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // 단어
            HStack(spacing: 6) {
                Text(word)
                    .font(.title.bold())
                SpeakButton(text: word, id: "word-\(word)", font: .title3)
            }

            // 문장 컨텍스트
            Text(highlightedSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // 뜻 목록
            if isLoading {
                ProgressView()
                    .frame(height: 40)
            } else if meanings.isEmpty {
                Text("뜻을 찾을 수 없습니다")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else if isSaved {
                Label("이미 저장된 단어입니다", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                ScrollView {
                    MeaningSelectionGrid(meanings: meanings, selected: $selected)
                        .padding(.horizontal, 20)
                }
                .frame(maxHeight: 200)
            }

            Spacer(minLength: 0)

            // 저장 버튼
            if !isLoading && !meanings.isEmpty && !isSaved {
                Button {
                    vocabulary.save(word, meaning: selectedText, sentence: sentence, lessonDate: lessonDate)
                    dismiss()
                } label: {
                    Label("단어장에 저장", systemImage: "bookmark.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selected.isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selected.isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .task {
            meanings = await DictionaryService.shared.lookup(word)
            // 뜻이 1개면 자동 선택
            if meanings.count == 1, let first = meanings.first {
                selected.insert(first.id)
            }
            isLoading = false
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
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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

            Spacer(minLength: 4)

            Button {
                onSave()
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.callout)
                    .foregroundStyle(isSaved ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(isSaved)
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}

