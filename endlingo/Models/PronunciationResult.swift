import SwiftUI

struct PronunciationResult {
    let score: Int
    let wordResults: [WordResult]
    let spokenWordResults: [WordResult]
    let spokenText: String

    struct WordResult: Identifiable {
        let id = UUID()
        let word: String
        let status: Status

        enum Status {
            case correct
            case close
            case wrong

            var color: Color {
                switch self {
                case .correct: return .green
                case .close: return .orange
                case .wrong: return .red
                }
            }
        }
    }

    var grade: Grade {
        switch score {
        case 90...100: return .excellent
        case 70..<90: return .good
        case 50..<70: return .fair
        default: return .needsPractice
        }
    }

    enum Grade {
        case excellent, good, fair, needsPractice

        var emoji: String {
            switch self {
            case .excellent: return "🌟"
            case .good: return "👍"
            case .fair: return "💪"
            case .needsPractice: return "📖"
            }
        }

        var message: String {
            switch self {
            case .excellent: return String(localized: "완벽해요!")
            case .good: return String(localized: "잘했어요!")
            case .fair: return String(localized: "좋은 시도예요!")
            case .needsPractice: return String(localized: "다시 도전해보세요!")
            }
        }

        var color: Color {
            switch self {
            case .excellent: return .yellow
            case .good: return .green
            case .fair: return .orange
            case .needsPractice: return .red
            }
        }
    }
}

// MARK: - Scoring (LCS 기반)

enum PronunciationScorer {
    static func score(reference: String, spoken: String) -> PronunciationResult {
        let refWords = normalize(reference)
        let spokenWords = normalize(spoken)

        guard !refWords.isEmpty else {
            return PronunciationResult(score: 0, wordResults: [], spokenWordResults: [], spokenText: spoken)
        }

        guard !spokenWords.isEmpty else {
            let missed = refWords.map { PronunciationResult.WordResult(word: $0, status: .wrong) }
            return PronunciationResult(score: 0, wordResults: missed, spokenWordResults: [], spokenText: spoken)
        }

        let m = refWords.count
        let n = spokenWords.count

        // LCS DP - 가중치: exact=2, close=1
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                let q = matchQuality(refWords[i - 1], spokenWords[j - 1])
                if q > 0 {
                    dp[i][j] = max(dp[i - 1][j - 1] + q, dp[i - 1][j], dp[i][j - 1])
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack으로 매칭 결과 추출
        var refStatuses = Array(repeating: PronunciationResult.WordResult.Status.wrong, count: m)
        var spokenStatuses = Array(repeating: PronunciationResult.WordResult.Status.wrong, count: n)
        var i = m, j = n
        while i > 0 && j > 0 {
            let q = matchQuality(refWords[i - 1], spokenWords[j - 1])
            if q > 0 && dp[i][j] == dp[i - 1][j - 1] + q {
                let status: PronunciationResult.WordResult.Status = q == 2 ? .correct : .close
                refStatuses[i - 1] = status
                spokenStatuses[j - 1] = status
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        let wordResults = refWords.enumerated().map {
            PronunciationResult.WordResult(word: $0.element, status: refStatuses[$0.offset])
        }

        let spokenWordResults = spokenWords.enumerated().map {
            PronunciationResult.WordResult(word: $0.element, status: spokenStatuses[$0.offset])
        }

        let correctCount = wordResults.filter { $0.status == .correct }.count
        let closeCount = wordResults.filter { $0.status == .close }.count
        let rawScore = Double(correctCount * 100 + closeCount * 50) / Double(m * 100) * 100
        let finalScore = min(100, Int(rawScore.rounded()))

        return PronunciationResult(
            score: finalScore,
            wordResults: wordResults,
            spokenWordResults: spokenWordResults,
            spokenText: spoken
        )
    }

    // MARK: - Private

    /// 두 단어의 매칭 품질: 2=정확, 1=유사, 0=불일치
    private static func matchQuality(_ a: String, _ b: String) -> Int {
        if a == b { return 2 }
        if levenshtein(a, b) <= 2 { return 1 }
        return 0
    }

    /// 텍스트 정규화: 소문자 → 축약형 확장 → 구두점 제거 → 단어 분리
    private static func normalize(_ text: String) -> [String] {
        var s = text.lowercased()

        // 스마트 따옴표/아포스트로피 통일
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")

        // 축약형 확장 (음성인식 결과와 원문 차이 해소)
        for (contraction, expansion) in contractions {
            s = s.replacingOccurrences(of: contraction, with: expansion)
        }

        // 구두점 제거
        let cleaned = s.unicodeScalars
            .filter { !CharacterSet.punctuationCharacters.contains($0) }
            .map { String($0) }
            .joined()

        return cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let m = s1.count, n = s2.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        let a = Array(s1), b = Array(s2)
        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
        return dp[m][n]
    }

    // MARK: - 축약형 사전

    private static let contractions: [String: String] = [
        "i'm": "i am",
        "i've": "i have",
        "i'll": "i will",
        "i'd": "i would",
        "don't": "do not",
        "doesn't": "does not",
        "didn't": "did not",
        "isn't": "is not",
        "aren't": "are not",
        "wasn't": "was not",
        "weren't": "were not",
        "won't": "will not",
        "wouldn't": "would not",
        "couldn't": "could not",
        "shouldn't": "should not",
        "can't": "can not",
        "it's": "it is",
        "that's": "that is",
        "he's": "he is",
        "she's": "she is",
        "we're": "we are",
        "they're": "they are",
        "you're": "you are",
        "we've": "we have",
        "they've": "they have",
        "you've": "you have",
        "we'll": "we will",
        "they'll": "they will",
        "you'll": "you will",
        "there's": "there is",
        "here's": "here is",
        "what's": "what is",
        "who's": "who is",
        "let's": "let us",
        "how's": "how is",
        "where's": "where is",
        "when's": "when is",
        "hadn't": "had not",
        "hasn't": "has not",
        "haven't": "have not",
        "might've": "might have",
        "must've": "must have",
        "should've": "should have",
        "would've": "would have",
        "could've": "could have",
    ]
}
