import SwiftUI

enum VocabularyTab: CaseIterable {
    case words, grammar

    var title: String {
        switch self {
        case .words: return String(localized: "단어")
        case .grammar: return String(localized: "문법")
        }
    }
}

struct VocabularyView: View {
    @State private var vocabulary = VocabularyService.shared
    @State private var grammarService = GrammarService.shared
    @State private var selectedTab: VocabularyTab = .words
    @State private var showAddSheet = false
    @State private var showWordQuiz = false
    @State private var showGrammarQuiz = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 세그먼트 탭
                Picker("탭", selection: $selectedTab) {
                    ForEach(VocabularyTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 탭 콘텐츠
                switch selectedTab {
                case .words:
                    wordContent
                case .grammar:
                    grammarContent
                }
            }
            .sheet(isPresented: $showWordQuiz) {
                QuizView()
            }
            .sheet(isPresented: $showGrammarQuiz) {
                GrammarQuizView()
            }
            .navigationTitle("단어장")
            .toolbar {
                if selectedTab == .words {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddWordSheet()
            }
        }
    }

    // MARK: - 단어 콘텐츠

    @ViewBuilder
    private var wordContent: some View {
        if vocabulary.words.isEmpty {
            wordEmptyView
        } else {
            wordList
        }
    }

    private var wordList: some View {
        List {
            // 퀴즈 버튼
            Button {
                showWordQuiz = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("단어 퀴즈")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("영단어 실력을 테스트하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            ForEach(vocabulary.words) { entry in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.word)
                            .font(.headline)

                        if let meaning = entry.meaning {
                            Text(meaning)
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.8))
                        }

                        if !entry.sentence.isEmpty {
                            Text(entry.sentence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    SpeakButton(text: entry.word, id: "vocab-\(entry.id)")
                }
                .padding(.vertical, 4)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    vocabulary.remove(id: vocabulary.words[index].id)
                }
            }
        }
    }

    private var wordEmptyView: some View {
        VStack(spacing: 16) {
            // 퀴즈 버튼
            Button {
                showWordQuiz = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("단어 퀴즈")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("영단어 실력을 테스트하세요")
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
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("저장한 단어가 없습니다")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("레슨에서 단어를 탭하거나\n+ 버튼으로 직접 추가하세요")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 문법 콘텐츠

    @ViewBuilder
    private var grammarContent: some View {
        if grammarService.grammars.isEmpty {
            grammarEmptyView
        } else {
            grammarList
        }
    }

    private var grammarList: some View {
        List {
            // 문법 퀴즈 버튼
            Button {
                showGrammarQuiz = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("문법 퀴즈")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("문법 실력을 테스트하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            ForEach(grammarService.grammars) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.pattern)
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Text(entry.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.8))

                    if let example = entry.example, !example.isEmpty {
                        Text("e.g. \(example)")
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    }

                    if !entry.sentence.isEmpty {
                        Text(entry.sentence)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    grammarService.remove(id: grammarService.grammars[index].id)
                }
            }
        }
    }

    private var grammarEmptyView: some View {
        VStack(spacing: 16) {
            // 문법 퀴즈 버튼
            Button {
                showGrammarQuiz = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("문법 퀴즈")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("문법 실력을 테스트하세요")
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
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("저장한 문법이 없습니다")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("레슨의 문법 포인트에서\n북마크 버튼을 눌러 저장하세요")
                .font(.caption)
                .foregroundStyle(.purple)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 단어 추가 시트

private struct AddWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vocabulary = VocabularyService.shared

    @State private var wordInput = ""
    @State private var meanings: [WordMeaning] = []
    @State private var selected: Set<UUID> = []
    @State private var isSearching = false
    @State private var searched = false

    private var canSearch: Bool {
        !wordInput.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching
    }

    private var selectedText: String? {
        WordMeaning.formatSelected(from: meanings, selected: selected)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 입력 필드
                HStack(spacing: 12) {
                    TextField("영어 단어 입력", text: $wordInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onSubmit { search() }

                    Button {
                        search()
                    } label: {
                        Group {
                            if isSearching {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .frame(width: 48, height: 48)
                        .background(canSearch ? Color.blue : Color.gray.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSearch)
                }
                .padding(.horizontal, 20)

                // 검색 결과
                if searched {
                    Text(wordInput.trimmingCharacters(in: .whitespaces).lowercased())
                        .font(.title2.bold())

                    if meanings.isEmpty {
                        Text("뜻을 찾을 수 없습니다")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else if vocabulary.isSaved(wordInput.trimmingCharacters(in: .whitespaces)) {
                        Label("이미 저장된 단어입니다", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        ScrollView {
                            MeaningSelectionGrid(meanings: meanings, selected: $selected)
                                .padding(.horizontal, 20)
                        }
                    }
                }

                Spacer(minLength: 0)

                // 저장 버튼
                if searched && !meanings.isEmpty && !vocabulary.isSaved(wordInput.trimmingCharacters(in: .whitespaces)) {
                    Button {
                        saveWord()
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 20)
            .navigationTitle("단어 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func search() {
        guard canSearch else { return }
        isSearching = true
        meanings = []
        selected = []
        searched = false

        Task {
            meanings = await DictionaryService.shared.lookup(wordInput)
            if meanings.count == 1, let first = meanings.first {
                selected.insert(first.id)
            }
            isSearching = false
            searched = true
        }
    }

    private func saveWord() {
        let trimmed = wordInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }

        vocabulary.save(trimmed, meaning: selectedText, sentence: "", lessonDate: SupabaseConfig.todayDateString)
        dismiss()
    }
}
