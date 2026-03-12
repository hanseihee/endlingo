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
        guard let url = Bundle.main.url(forResource: "builtin_words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BuiltInWord].self, from: data) else {
            print("Failed to load builtin_words.json")
            return
        }
        words = decoded
    }
}
