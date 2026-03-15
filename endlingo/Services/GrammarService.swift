import Foundation

@Observable
@MainActor
final class GrammarService {
    static let shared = GrammarService()

    private(set) var grammars: [SavedGrammar] = []

    private let fileURL: URL
    private var auth: AuthService { AuthService.shared }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("saved_grammar.json")
        loadLocal()
    }

    // MARK: - Public API

    func save(pattern: String, explanation: String, example: String?, sentence: String, lessonDate: String) {
        guard !isSaved(pattern) else { return }

        let entry = SavedGrammar(
            id: UUID(), userId: auth.isLoggedIn ? auth.userId : nil,
            pattern: pattern, explanation: explanation, example: example,
            sentence: sentence, lessonDate: lessonDate, savedAt: Date()
        )
        grammars.insert(entry, at: 0)

        if auth.isLoggedIn {
            Task {
                guard let token = await auth.accessToken else { return }
                await SupabaseAPI.insert(entry, table: "saved_grammar", token: token)
            }
        } else {
            persistLocal()
        }

        GamificationService.shared.awardGrammarSaveXP()
        AnalyticsService.logGrammarSave(pattern: pattern)
    }

    func remove(id: UUID) {
        grammars.removeAll { $0.id == id }

        if auth.isLoggedIn {
            Task {
                guard let token = await auth.accessToken else { return }
                await SupabaseAPI.delete("saved_grammar", filter: "id=eq.\(id.uuidString)", token: token)
            }
        } else {
            persistLocal()
        }
    }

    func isSaved(_ pattern: String) -> Bool {
        grammars.contains { $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame }
    }

    /// 로그인 시 호출: 로컬 문법을 서버에 업로드 후 서버 문법 로드
    func syncAfterLogin() async {
        guard let token = await auth.accessToken, let userId = auth.userId else { return }

        let localGrammars = loadLocalGrammars()
        for grammar in localGrammars {
            let entry = SavedGrammar(
                id: grammar.id, userId: userId,
                pattern: grammar.pattern, explanation: grammar.explanation,
                example: grammar.example, sentence: grammar.sentence,
                lessonDate: grammar.lessonDate, savedAt: grammar.savedAt
            )
            await SupabaseAPI.insert(entry, table: "saved_grammar", token: token)
        }

        // 서버에서 전체 로드 성공 후에만 로컬 파일 삭제
        let remote: [SavedGrammar] = await SupabaseAPI.fetch(
            "saved_grammar", query: "select=*&order=saved_at.desc", token: token
        )
        if !remote.isEmpty || localGrammars.isEmpty {
            grammars = remote
            if !localGrammars.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    func clearAfterLogout() {
        grammars = []
    }

    // MARK: - Local Storage

    private func loadLocal() {
        grammars = loadLocalGrammars()
    }

    private func loadLocalGrammars() -> [SavedGrammar] {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? SupabaseAPI.decoder.decode([SavedGrammar].self, from: data) else { return [] }
        return loaded
    }

    private func persistLocal() {
        guard let data = try? SupabaseAPI.encoder.encode(grammars) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
