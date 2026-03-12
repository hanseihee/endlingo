import SwiftUI

struct VocabularyView: View {
    @State private var vocabulary = VocabularyService.shared

    var body: some View {
        NavigationStack {
            Group {
                if vocabulary.words.isEmpty {
                    emptyView
                } else {
                    wordList
                }
            }
            .navigationTitle("단어장")
        }
    }

    private var wordList: some View {
        List {
            ForEach(vocabulary.words) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.word)
                        .font(.headline)

                    Text(entry.sentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(entry.lessonDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("저장한 단어가 없습니다")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("레슨에서 단어를 탭하여 저장하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
