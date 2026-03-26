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
        let spokenWords = normalize(spoken)

        // 표준 숫자 변환 (405 → "four hundred five")
        let refStandard = normalize(reference)
        // 자릿수별 변환 (405 → "four zero five")
        let refDigits = normalizeDigitByDigit(reference)

        let result1 = computeResult(refWords: refStandard, spokenWords: spokenWords, spokenText: spoken)

        // 자릿수별 변환이 다른 경우만 2차 채점
        if refDigits != refStandard {
            let result2 = computeResult(refWords: refDigits, spokenWords: spokenWords, spokenText: spoken)
            if result2.score > result1.score {
                return result2
            }
        }

        return result1
    }

    /// LCS DP 기반 채점 (공통 로직)
    private static func computeResult(refWords: [String], spokenWords: [String], spokenText: String) -> PronunciationResult {
        guard !refWords.isEmpty else {
            return PronunciationResult(score: 0, wordResults: [], spokenWordResults: [], spokenText: spokenText)
        }

        guard !spokenWords.isEmpty else {
            let missed = refWords.map { PronunciationResult.WordResult(word: $0, status: .wrong) }
            return PronunciationResult(score: 0, wordResults: missed, spokenWordResults: [], spokenText: spokenText)
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
            spokenText: spokenText
        )
    }

    // MARK: - Private

    /// 두 단어의 매칭 품질: 2=정확, 1=유사, 0=불일치
    private static func matchQuality(_ a: String, _ b: String) -> Int {
        if a == b { return 2 }
        if levenshtein(a, b) <= 2 { return 1 }
        return 0
    }

    /// 텍스트 정규화: 소문자 → 축약형 확장 → 구두점 제거 → 숫자→영어 → 단어 분리
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

        // 단어 분리 후 숫자를 영어로 변환
        let words = cleaned.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .flatMap { numberToWords($0) }

        // "oh"/"o"를 "zero"로 매핑 (숫자 읽기에서 0을 oh로 발음하는 경우)
        return words.map { $0 == "oh" || $0 == "o" ? "zero" : $0 }
    }

    /// 숫자를 자릿수별 단어로 변환하는 정규화 (405 → "four zero five")
    /// 음성인식이 숫자를 자릿수별로 읽는 경우를 처리
    private static func normalizeDigitByDigit(_ text: String) -> [String] {
        var s = text.lowercased()

        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "\u{2018}", with: "'")

        for (contraction, expansion) in contractions {
            s = s.replacingOccurrences(of: contraction, with: expansion)
        }

        let cleaned = s.unicodeScalars
            .filter { !CharacterSet.punctuationCharacters.contains($0) }
            .map { String($0) }
            .joined()

        let words = cleaned.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .flatMap { numberToDigitWords($0) }

        return words.map { $0 == "oh" || $0 == "o" ? "zero" : $0 }
    }

    /// 숫자를 개별 자릿수 단어로 변환: "405" → ["four", "zero", "five"]
    private static func numberToDigitWords(_ token: String) -> [String] {
        // 서수는 기존 방식 유지
        if let ordinal = parseOrdinal(token) {
            return [ordinal]
        }

        guard token.allSatisfy({ $0.isNumber }), !token.isEmpty else {
            return [token]
        }

        // 1자리 숫자는 기존 방식과 동일
        if token.count == 1 {
            return numberToWords(token)
        }

        // 2자리 이상 숫자 → 자릿수별 단어로 분해
        return token.map { char -> String in
            if let digit = Int(String(char)), let word = numberWordMap[digit] {
                return word
            }
            return String(char)
        }
    }

    /// 숫자 토큰을 영어 단어로 변환. 숫자가 아니면 그대로 반환.
    /// "7" → ["seven"], "15" → ["fifteen"], "123" → ["one", "hundred", "twenty", "three"]
    /// 서수 표현도 처리: "1st" → ["first"], "3rd" → ["third"]
    private static func numberToWords(_ token: String) -> [String] {
        // 서수 표현 처리 (1st, 2nd, 3rd, 4th, ...)
        if let ordinal = parseOrdinal(token) {
            return [ordinal]
        }

        guard let num = Int(token), num >= 0, num <= 9999 else {
            return [token]
        }

        if let simple = numberWordMap[num] {
            return simple.components(separatedBy: " ")
        }

        var parts: [String] = []
        var n = num

        if n >= 1000 {
            let thousands = n / 1000
            if let w = numberWordMap[thousands] {
                parts.append(w)
            }
            parts.append("thousand")
            n %= 1000
            if n == 0 { return parts }
        }

        if n >= 100 {
            let hundreds = n / 100
            if let w = numberWordMap[hundreds] {
                parts.append(w)
            }
            parts.append("hundred")
            n %= 100
            if n == 0 { return parts }
        }

        if let w = numberWordMap[n] {
            parts.append(contentsOf: w.components(separatedBy: " "))
        } else {
            let tens = (n / 10) * 10
            let ones = n % 10
            if let t = numberWordMap[tens] { parts.append(t) }
            if ones > 0, let o = numberWordMap[ones] { parts.append(o) }
        }

        return parts
    }

    /// "1st" → "first", "22nd" → nil (단순 서수만 처리)
    private static func parseOrdinal(_ token: String) -> String? {
        let suffixes = ["st", "nd", "rd", "th"]
        for suffix in suffixes {
            if token.hasSuffix(suffix), let num = Int(token.dropLast(suffix.count)) {
                if let word = ordinalWordMap[num] { return word }
            }
        }
        return nil
    }

    private static let numberWordMap: [Int: String] = [
        0: "zero", 1: "one", 2: "two", 3: "three", 4: "four",
        5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine",
        10: "ten", 11: "eleven", 12: "twelve", 13: "thirteen",
        14: "fourteen", 15: "fifteen", 16: "sixteen", 17: "seventeen",
        18: "eighteen", 19: "nineteen", 20: "twenty", 30: "thirty",
        40: "forty", 50: "fifty", 60: "sixty", 70: "seventy",
        80: "eighty", 90: "ninety",
    ]

    private static let ordinalWordMap: [Int: String] = [
        1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth",
        6: "sixth", 7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth",
        11: "eleventh", 12: "twelfth", 13: "thirteenth", 14: "fourteenth",
        15: "fifteenth", 16: "sixteenth", 17: "seventeenth", 18: "eighteenth",
        19: "nineteenth", 20: "twentieth", 21: "twenty first", 30: "thirtieth",
        31: "thirty first",
    ]

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
