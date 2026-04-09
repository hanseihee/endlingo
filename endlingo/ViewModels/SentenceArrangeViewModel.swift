import Foundation

struct ArrangeWord: Identifiable {
    let id = UUID()
    let text: String
    let originalIndex: Int
}

@Observable
@MainActor
final class SentenceArrangeViewModel {
    // 퀴즈 상태
    var isLoading = false
    var errorMessage: String?
    var currentSentenceKo = ""
    var correctWords: [String] = []
    var shuffledWords: [ArrangeWord] = []
    var placedWords: [ArrangeWord] = []
    var isChecked = false
    var isCorrect = false

    // 누적 점수
    var correctCount = 0
    var totalCount = 0
    var totalXPEarned = 0

    // 문장 풀
    private var sentencePool: [Scenario] = []
    private var usedIndices: Set<Int> = []
    private let gamification = GamificationService.shared

    // MARK: - 문장 로드

    func loadSentences() async {
        guard let levelRaw = UserDefaults.standard.string(forKey: "selectedLevel"),
              let envRaw = UserDefaults.standard.string(forKey: "selectedEnvironment"),
              let level = EnglishLevel(rawValue: levelRaw),
              let environment = LearningEnvironment(rawValue: envRaw) else {
            errorMessage = String(localized: "설정을 먼저 완료해주세요")
            return
        }

        isLoading = true
        errorMessage = nil

        let scenarios = await LessonService.shared.fetchSentencePool(level: level, environment: environment)

        if scenarios.isEmpty {
            errorMessage = String(localized: "문장을 불러올 수 없습니다")
            isLoading = false
            return
        }

        sentencePool = scenarios
        usedIndices = []
        isLoading = false
        nextSentence()
    }

    // MARK: - 다음 문장

    func nextSentence() {
        // 풀 소진 시 리셋
        if usedIndices.count >= sentencePool.count {
            usedIndices.removeAll()
        }

        // 미사용 문장 중 랜덤 선택
        let available = Set(sentencePool.indices).subtracting(usedIndices)
        guard let index = available.randomElement() else { return }

        usedIndices.insert(index)
        let scenario = sentencePool[index]

        let words = splitSentence(scenario.sentenceEn)
        correctWords = words

        currentSentenceKo = scenario.sentenceKo

        // 셔플 (정답과 같은 순서가 나오지 않도록)
        var shuffled = words.enumerated().map { ArrangeWord(text: $1, originalIndex: $0) }
        repeat {
            shuffled.shuffle()
        } while shuffled.count > 1 && shuffled.map(\.text) == words

        shuffledWords = shuffled
        placedWords = []
        isChecked = false
        isCorrect = false
    }

    // 접속사/종속절 — 항상 앞에서 끊기
    private static let strongBreakWords: Set<String> = [
        "and", "but", "or", "so", "yet", "nor",
        "if", "when", "while", "because", "since", "although", "though",
        "before", "after", "until", "unless", "whether",
        "that", "which", "who", "whose", "where", "whom",
        "then", "however", "therefore", "also", "instead",
    ]

    // 전치사 — 현재 덩어리가 2단어 이상일 때만 끊기
    private static let weakBreakWords: Set<String> = [
        "to", "for", "with", "without", "about", "into", "from",
        "at", "in", "on", "by", "of", "as", "through", "during",
        "between", "among", "under", "over", "above", "below",
    ]

    private func splitSentence(_ sentence: String) -> [String] {
        let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count > 4 else { return words }

        var chunks: [String] = []
        var current: [String] = []

        for word in words {
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

            let isStrongBreak = Self.strongBreakWords.contains(lower)
            let isWeakBreak = Self.weakBreakWords.contains(lower)

            if isStrongBreak && !current.isEmpty {
                // 접속사/종속절 앞에서 끊기
                chunks.append(current.joined(separator: " "))
                current = [word]
            } else if isWeakBreak && current.count >= 2 {
                // 전치사 앞에서 끊기 (이미 2단어 이상 쌓였을 때)
                chunks.append(current.joined(separator: " "))
                current = [word]
            } else {
                current.append(word)

                // 구두점 뒤에서 끊기 (마침표, 쉼표, 세미콜론 등)
                let last = word.last
                if last == "." || last == "," || last == ";" || last == "!" || last == "?" || last == ":" {
                    chunks.append(current.joined(separator: " "))
                    current = []
                }
            }
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: " "))
        }

        // 1단어 덩어리를 이전 덩어리에 병합
        var merged: [String] = []
        for chunk in chunks {
            let wordCount = chunk.components(separatedBy: " ").count
            if wordCount == 1 && !merged.isEmpty {
                merged[merged.count - 1] += " " + chunk
            } else {
                merged.append(chunk)
            }
        }

        // 덩어리가 2개 미만이면 단어 단위로 fallback
        return merged.count >= 2 ? merged : words
    }

    // MARK: - 단어 선택/취소

    func selectWord(_ word: ArrangeWord) {
        guard !isChecked else { return }
        if let index = shuffledWords.firstIndex(where: { $0.id == word.id }) {
            shuffledWords.remove(at: index)
            placedWords.append(word)
        }
    }

    func deselectWord(_ word: ArrangeWord) {
        guard !isChecked else { return }
        if let index = placedWords.firstIndex(where: { $0.id == word.id }) {
            placedWords.remove(at: index)
            shuffledWords.append(word)
        }
    }

    // MARK: - 채점

    var canCheck: Bool {
        shuffledWords.isEmpty && !placedWords.isEmpty && !isChecked
    }

    func checkAnswer() {
        guard canCheck else { return }
        isChecked = true
        totalCount += 1

        let answer = placedWords.map(\.text)
        isCorrect = answer == correctWords

        if isCorrect {
            correctCount += 1
            let xp = GamificationService.XP.quizCorrect
            totalXPEarned += xp
            gamification.recordQuizAnswer(
                wordId: UUID(),
                word: correctWords.joined(separator: " "),
                quizType: "sentence_arrange",
                isCorrect: true
            )
        } else {
            gamification.recordQuizAnswer(
                wordId: UUID(),
                word: correctWords.joined(separator: " "),
                quizType: "sentence_arrange",
                isCorrect: false
            )
        }
    }

    // MARK: - 건너뛰기

    func skip() {
        totalCount += 1
        nextSentence()
    }

    // MARK: - 재시도

    func retry() {
        isChecked = false
        isCorrect = false
        // 배치된 단어를 다시 선택지로 돌림
        shuffledWords.append(contentsOf: placedWords)
        placedWords.removeAll()
        shuffledWords.shuffle()
    }
}
