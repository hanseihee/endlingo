import Foundation

struct WordMeaning: Identifiable, Hashable {
    let id = UUID()
    let pos: String         // (명), (동) 등
    let text: String        // 한국어 뜻
    let synonyms: [String]  // 영어 동의어

    /// 선택된 뜻을 품사별로 그룹핑하여 문자열로 반환
    /// 예: "(동) 맞다, 알맞다 (명) 발작"
    static func formatSelected(from meanings: [WordMeaning], selected: Set<UUID>) -> String? {
        let items = meanings.filter { selected.contains($0.id) }
        guard !items.isEmpty else { return nil }

        var groups: [(pos: String, entries: [(text: String, synonyms: [String])])] = []
        for item in items {
            if let last = groups.last, last.pos == item.pos {
                groups[groups.count - 1].entries.append((text: item.text, synonyms: item.synonyms))
            } else {
                groups.append((pos: item.pos, entries: [(text: item.text, synonyms: item.synonyms)]))
            }
        }

        return groups.map { group in
            let joined = group.entries.map { entry in
                if entry.synonyms.isEmpty {
                    return entry.text
                } else {
                    return "\(entry.text) (\(entry.synonyms.joined(separator: ", ")))"
                }
            }.joined(separator: ", ")
            return group.pos.isEmpty ? joined : "(\(group.pos)) \(joined)"
        }.joined(separator: " ")
    }
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

        // [0][0][0] = 대표 번역
        var primaryText: String?
        if let translations = json[safe: 0] as? [Any],
           let first = translations[safe: 0] as? [Any],
           let primary = first[safe: 0] as? String {
            primaryText = primary
        }

        // [1] = dictionary entries by part of speech
        // [1][n][2] = reverse translations with English synonyms
        if let dictEntries = json[safe: 1] as? [Any] {
            for entry in dictEntries {
                guard let posArray = entry as? [Any],
                      let pos = posArray[safe: 0] as? String,
                      let meanings = posArray[safe: 1] as? [String] else { continue }

                // 동의어 맵 구축: 한국어 뜻 → 영어 동의어 배열
                var synonymMap: [String: [String]] = [:]
                if let reverseEntries = posArray[safe: 2] as? [Any] {
                    for rev in reverseEntries {
                        guard let revArray = rev as? [Any],
                              let korean = revArray[safe: 0] as? String,
                              let english = revArray[safe: 1] as? [String] else { continue }
                        synonymMap[korean] = english
                    }
                }

                let label = posLabel(pos)
                for m in meanings {
                    let syns = synonymMap[m] ?? []
                    results.append(WordMeaning(pos: label, text: m, synonyms: syns))
                }
            }
        }

        // 대표 번역을 맨 위로 이동
        if let primaryText,
           let idx = results.firstIndex(where: { $0.text == primaryText }) {
            let item = results.remove(at: idx)
            results.insert(item, at: 0)
        } else if let primaryText, results.isEmpty {
            // 사전 항목이 없을 때만 대표 번역을 fallback으로 추가
            results.insert(WordMeaning(pos: "", text: primaryText, synonyms: []), at: 0)
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
