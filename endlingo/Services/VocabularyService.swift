import Foundation

@Observable
@MainActor
final class VocabularyService {
    static let shared = VocabularyService()

    private(set) var words: [SavedWord] = []

    private let baseURL = "https://alvawqinuacabfnqduoy.supabase.co/rest/v1"
    private let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsdmF3cWludWFjYWJmbnFkdW95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNjExNDgsImV4cCI6MjA4ODgzNzE0OH0.C-gnavFBHa-gIyvoGngaYfV6htDTiFyOmj5MemIlzhY"

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

    private var auth: AuthService { AuthService.shared }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("saved_words.json")
        loadLocal()
    }

    // MARK: - Public API

    func save(_ word: String, meaning: String?, sentence: String, lessonDate: String) {
        guard !isSaved(word) else { return }

        if auth.isLoggedIn, let userId = auth.userId {
            let entry = SavedWord(
                id: UUID(), userId: userId,
                word: word, meaning: meaning, sentence: sentence,
                lessonDate: lessonDate, savedAt: Date()
            )
            words.insert(entry, at: 0)
            Task { await remoteInsert(entry) }
        } else {
            let entry = SavedWord(
                id: UUID(), userId: nil,
                word: word, meaning: meaning, sentence: sentence,
                lessonDate: lessonDate, savedAt: Date()
            )
            words.insert(entry, at: 0)
            persistLocal()
        }
    }

    func remove(id: UUID) {
        guard let entry = words.first(where: { $0.id == id }) else { return }
        words.removeAll { $0.id == id }

        if auth.isLoggedIn {
            Task { await remoteDelete(id) }
        } else {
            persistLocal()
        }
    }

    func isSaved(_ word: String) -> Bool {
        words.contains { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    /// 로그인 시 호출: 로컬 단어를 서버에 업로드 후 서버 단어 로드
    func syncAfterLogin() async {
        guard let userId = auth.userId else { return }

        // 로컬에 저장된 게스트 단어를 서버에 업로드
        let localWords = loadLocalWords()
        for word in localWords {
            let entry = SavedWord(
                id: word.id, userId: userId,
                word: word.word, meaning: word.meaning,
                sentence: word.sentence,
                lessonDate: word.lessonDate, savedAt: word.savedAt
            )
            await remoteInsert(entry)
        }

        // 로컬 파일 정리
        if !localWords.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // 서버에서 전체 단어 로드
        await fetchRemote()
    }

    /// 기화
    func clearAfterLogout() {
        words = []
    }

    // MARK: - Remote (Supabase)

    private func fetchRemote() async {
        guard let token = await auth.accessToken else { return }

        let urlString = "\(baseURL)/saved_words?select=*&order=saved_at.desc"
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            words = try decoder.decode([SavedWord].self, from: data)
        } catch {
            print("Fetch words error: \(error)")
        }
    }

    private func remoteInsert(_ entry: SavedWord) async {
        guard let token = await auth.accessToken else { return }

        let urlString = "\(baseURL)/saved_words"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? encoder.encode(entry)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("Insert word error: \(http.statusCode)")
            }
        } catch {
            print("Insert word error: \(error)")
        }
    }

    private func remoteDelete(_ id: UUID) async {
        guard let token = await auth.accessToken else { return }

        let urlString = "\(baseURL)/saved_words?id=eq.\(id.uuidString)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("Delete word error: \(error)")
        }
    }

    // MARK: - Local Storage (게스트용)

    private func loadLocal() {
        words = loadLocalWords()
    }

    private func loadLocalWords() -> [SavedWord] {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? decoder.decode([SavedWord].self, from: data) else { return [] }
        return loaded
    }

    private func persistLocal() {
        guard let data = try? encoder.encode(words) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
