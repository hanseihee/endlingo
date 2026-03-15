import Foundation

@Observable
@MainActor
final class VocabularyService {
    static let shared = VocabularyService()

    private(set) var words: [SavedWord] = []

    private let fileURL: URL
    private var auth: AuthService { AuthService.shared }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("saved_words.json")
        loadLocal()
    }

    // MARK: - Public API

    func save(_ word: String, meaning: String?, sentence: String, lessonDate: String) {
        guard !isSaved(word) else { return }

        let entry = SavedWord(
            id: UUID(), userId: auth.isLoggedIn ? auth.userId : nil,
            word: word, meaning: meaning, sentence: sentence,
            lessonDate: lessonDate, savedAt: Date()
        )
        words.insert(entry, at: 0)

        if auth.isLoggedIn {
            Task {
                guard let token = await auth.accessToken else { return }
                await SupabaseAPI.insert(entry, table: "saved_words", token: token)
            }
        } else {
            persistLocal()
        }

        GamificationService.shared.awardWordSaveXP()
        AnalyticsService.logWordSave(word: word)
    }

    func remove(id: UUID) {
        words.removeAll { $0.id == id }

        if auth.isLoggedIn {
            Task {
                guard let token = await auth.accessToken else { return }
                await SupabaseAPI.delete("saved_words", filter: "id=eq.\(id.uuidString)", token: token)
            }
        } else {
            persistLocal()
        }
    }

    func isSaved(_ word: String) -> Bool {
        words.contains { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// 로그인 시 호출: 로컬 단어를 서버에 업로드 후 서버 단어 로드
    func syncAfterLogin() async {
        guard let token = await auth.accessToken, let userId = auth.userId else { return }

        let localWords = loadLocalWords()
        for word in localWords {
            let entry = SavedWord(
                id: word.id, userId: userId,
                word: word.word, meaning: word.meaning,
                sentence: word.sentence,
                lessonDate: word.lessonDate, savedAt: word.savedAt
            )
            await SupabaseAPI.insert(entry, table: "saved_words", token: token)
        }

        // 서버에서 전체 로드 성공 후에만 로컬 파일 삭제
        let remote: [SavedWord] = await SupabaseAPI.fetch(
            "saved_words", query: "select=*&order=saved_at.desc", token: token
        )
        if !remote.isEmpty || localWords.isEmpty {
            words = remote
            if !localWords.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    func clearAfterLogout() {
        words = []
    }

    // MARK: - Local Storage

    private func loadLocal() {
        words = loadLocalWords()
    }

    private func loadLocalWords() -> [SavedWord] {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? SupabaseAPI.decoder.decode([SavedWord].self, from: data) else { return [] }
        return loaded
    }

    private func persistLocal() {
        guard let data = try? SupabaseAPI.encoder.encode(words) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
