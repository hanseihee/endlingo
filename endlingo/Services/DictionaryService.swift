import Foundation

struct WordMeaning: Identifiable, Hashable {
    let id = UUID()
    let pos: String      // (명), (동) 등
    let text: String     // 한국어 뜻
}

final class DictionaryService {
    static let shared = DictionaryService()

    private init() {}

    /// Google Translate API로 영단어의 한국어 뜻 목록을 조회
    func lookup(_ word: String) async -> [WordMeaning] {
        let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        guard !cleaned.isEmpty,
              let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ko&dt=t&dt=bd&q=\(encoded)")
        else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseResponse(data)
        } catch {
            return []
        }
    }

    private func parseResponse(_ data: Data) -> [WordMeaning] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }

        var results: [WordMeaning] = []

        // [1] = dictionary entries by part of speech
        if let dictEntries = json[safe: 1] as? [Any] {
            for entry in dictEntries {
                guard let posArray = entry as? [Any],
                      let pos = posArray[safe: 0] as? String,
                      let meanings = posArray[safe: 1] as? [String] else { continue }
                let label = posLabel(pos)
                for m in meanings {
                    results.append(WordMeaning(pos: label, text: m))
                }
            }
        }

        // fallback: simple translation
        if results.isEmpty,
           let translations = json[safe: 0] as? [Any],
           let first = translations[safe: 0] as? [Any],
           let korean = first[safe: 0] as? String {
            results.append(WordMeaning(pos: "", text: korean))
        }

        return results
    }

    private func posLabel(_ pos: String) -> String {
        switch pos {
        case "noun": return "명"
        case "verb": return "동"
        case "adjective": return "형"
        case "adverb": return "부"
        case "preposition": return "전"
        case "conjunction": return "접"
        case "pronoun": return "대"
        case "interjection": return "감"
        default: return pos
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
