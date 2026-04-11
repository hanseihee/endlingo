import Foundation

@MainActor
final class BuiltInWordBank {
    static let shared = BuiltInWordBank()

    private(set) var words: [BuiltInWord] = []

    var isLoaded: Bool { !words.isEmpty }

    private init() {
        loadWords()
    }

    private func loadWords() {
        let lang = Locale.current.language.languageCode?.identifier ?? "ko"
        let filename: String
        switch lang {
        case "ja": filename = "builtin_words_ja"
        case "vi": filename = "builtin_words_vi"
        default: filename = "builtin_words"
        }

        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BuiltInWord].self, from: data) else {
            print("Failed to load \(filename).json")
            return
        }
        words = decoded
    }
}
