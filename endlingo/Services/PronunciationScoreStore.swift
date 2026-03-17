import Foundation

enum PronunciationScoreStore {
    private static let key = "pronunciationScores"
    private static let maxDays = 30

    static func save(score: Int, date: String, index: Int) {
        var scores = loadAll()
        scores["\(date)_\(index)"] = score
        cleanup(&scores)
        UserDefaults.standard.set(scores, forKey: key)
    }

    static func load(date: String, index: Int) -> Int? {
        let scores = loadAll()
        let value = scores["\(date)_\(index)"]
        return value != nil && value! > 0 ? value : nil
    }

    private static func loadAll() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    /// 30일 이전 데이터 자동 정리
    private static func cleanup(_ scores: inout [String: Int]) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -maxDays, to: .now) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        scores = scores.filter { key, _ in
            let dateString = String(key.prefix(10))
            guard let date = formatter.date(from: dateString) else { return false }
            return date >= cutoff
        }
    }
}
