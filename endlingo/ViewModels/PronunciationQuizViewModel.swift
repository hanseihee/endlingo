import Foundation

struct PronunciationQuizQuestion {
    let word: String
    let meaning: String
    let wordId: UUID?
}

@Observable
@MainActor
final class PronunciationQuizViewModel {
    var questions: [PronunciationQuizQuestion] = []
    var currentIndex = 0
    var isFinished = false
    var correctCount = 0
    var totalXPEarned = 0

    // 현재 문제 상태
    var currentScore: Int?
    var isCorrect: Bool?
    var spokenText: String?

    // 외운 단어 관리
    private static let masteredKey = "pronunciationMasteredWords"

    private let gamification = GamificationService.shared
    private let passThreshold = 70

    var currentQuestion: PronunciationQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        questions.isEmpty ? 0 : Double(currentIndex) / Double(questions.count)
    }

    func canStart(source: QuizWordSource) -> Bool {
        wordCount(source: source) >= 5
    }

    func wordCount(source: QuizWordSource) -> Int {
        buildWordPool(source: source).count
    }

    func generate(source: QuizWordSource, count: Int = 10) {
        let pool = buildWordPool(source: source)
        guard pool.count >= 5 else { return }

        let selected = Array(pool.shuffled().prefix(min(count, pool.count)))
        questions = selected.map {
            PronunciationQuizQuestion(word: $0.word, meaning: $0.meaning, wordId: $0.id)
        }

        currentIndex = 0
        isFinished = false
        correctCount = 0
        totalXPEarned = 0
        currentScore = nil
        isCorrect = nil
        spokenText = nil
        AnalyticsService.logQuizStart(type: "pronunciation", source: source.title)
    }

    func judge(score: Int, spokenText: String? = nil) {
        guard let question = currentQuestion, currentScore == nil else { return }
        currentScore = score
        self.spokenText = spokenText
        let passed = score >= passThreshold
        isCorrect = passed

        if passed {
            correctCount += 1
        }

        let xp = passed ? GamificationService.XP.quizCorrect : 0
        totalXPEarned += xp

        gamification.recordQuizAnswer(
            wordId: question.wordId ?? UUID(),
            word: question.word,
            quizType: "pronunciation",
            isCorrect: passed
        )
    }

    func nextQuestion() {
        currentIndex += 1
        currentScore = nil
        isCorrect = nil
        spokenText = nil

        if currentIndex >= questions.count {
            isFinished = true
            AnalyticsService.logQuizComplete(
                type: "pronunciation",
                correct: correctCount,
                total: questions.count,
                xp: totalXPEarned
            )
        }
    }

    // MARK: - 외운 단어 관리

    func isMastered(_ word: String) -> Bool {
        masteredWords.contains(word.lowercased())
    }

    func toggleMastered(_ word: String) {
        let key = word.lowercased()
        var set = masteredWords
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
        UserDefaults.standard.set(Array(set), forKey: Self.masteredKey)
    }

    private var masteredWords: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: Self.masteredKey) ?? []
        return Set(arr)
    }

    // MARK: - Private

    private struct WordItem {
        let word: String
        let meaning: String
        let id: UUID?
    }

    private func buildWordPool(source: QuizWordSource) -> [WordItem] {
        let mastered = masteredWords
        var pool: [WordItem] = []

        if source == .saved || source == .mixed {
            let saved = VocabularyService.shared.words
                .filter { $0.meaning != nil && !mastered.contains($0.word.lowercased()) }
                .map { WordItem(word: $0.word, meaning: $0.meaning!, id: $0.id) }
            pool.append(contentsOf: saved)
        }

        if source == .builtin || source == .mixed {
            let builtin = BuiltInWordBank.shared.words
                .filter { !mastered.contains($0.word.lowercased()) }
                .map { WordItem(word: $0.word, meaning: $0.meaning, id: nil) }
            pool.append(contentsOf: builtin)
        }

        return pool
    }
}
