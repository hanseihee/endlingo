import Foundation

@Observable
final class VocabularyService {
    static let shared = VocabularyService()

    private(set) var words: [SavedWord] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("saved_words.json")
        load()
    }

    // MARK: - Public API (Supabase 전환 시 이 인터페이스 유지)

    func save(_ word: String, sentence: String, lessonDate: String) {
        guard !isSaved(word) else { return }

        let entry = SavedWord(
            id: UUID(),
            word: word,
            sentence: sentence,
            lessonDate: lessonDate,
            savedAt: Date()
        )
        words.insert(entry, at: 0)
        persist()
    }

    func remove(id: UUID) {
        words.removeAll { $0.id == id }
        persist()
    }

    func isSaved(_ word: String) -> Bool {
        words.contains { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    // MARK: - Local Storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? decoder.decode([SavedWord].self, from: data) else { return }
        words = loaded
    }

    private func persist() {
        guard let data = try? encoder.encode(words) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
