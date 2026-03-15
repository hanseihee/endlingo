import Foundation

enum GrammarQuizType: String {
    case patternToExplanation = "pattern_to_explanation"
    case explanationToPattern = "explanation_to_pattern"
}

struct GrammarQuizQuestion {
    let pattern: String
    let explanation: String
    let example: String?
    let grammarId: UUID?
    let quizType: GrammarQuizType
    let options: [String]
    let correctIndex: Int
}

@Observable
@MainActor
final class GrammarQuizViewModel {
    var questions: [GrammarQuizQuestion] = []
    var currentIndex = 0
    var selectedAnswer: Int?
    var isAnswered = false
    var isFinished = false
    var correctCount = 0
    var totalXPEarned = 0

    private let gamification = GamificationService.shared

    // MARK: - 외운 문법 관리

    private static let masteredKey = "masteredGrammar"

    private(set) var masteredGrammar: Set<String> = {
        let array = UserDefaults.standard.stringArray(forKey: masteredKey) ?? []
        return Set(array)
    }()

    var masteredCount: Int { masteredGrammar.count }

    func isMastered(_ pattern: String) -> Bool {
        masteredGrammar.contains(pattern.lowercased())
    }

    func toggleMastered(_ pattern: String) {
        let key = pattern.lowercased()
        if masteredGrammar.contains(key) {
            masteredGrammar.remove(key)
        } else {
            masteredGrammar.insert(key)
        }
        UserDefaults.standard.set(Array(masteredGrammar), forKey: Self.masteredKey)
    }

    var currentQuestion: GrammarQuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        questions.isEmpty ? 0 : Double(currentIndex) / Double(questions.count)
    }

    func canStartQuiz() -> Bool {
        let available = GrammarService.shared.grammars
            .filter { !masteredGrammar.contains($0.pattern.lowercased()) }
        return available.count >= 4
    }

    var availableCount: Int {
        GrammarService.shared.grammars
            .filter { !masteredGrammar.contains($0.pattern.lowercased()) }
            .count
    }

    func generateQuiz(type: GrammarQuizType, count: Int = 10) {
        let pool = GrammarService.shared.grammars
            .filter { !masteredGrammar.contains($0.pattern.lowercased()) }
        guard pool.count >= 4 else { return }

        let selected = Array(pool.shuffled().prefix(min(count, pool.count)))
        questions = selected.map { item in
            makeQuestion(item: item, type: type, allItems: pool)
        }

        currentIndex = 0
        selectedAnswer = nil
        isAnswered = false
        isFinished = false
        correctCount = 0
        totalXPEarned = 0
    }

    func selectAnswer(_ index: Int) {
        guard !isAnswered, let question = currentQuestion else { return }
        selectedAnswer = index
        isAnswered = true

        let isCorrect = index == question.correctIndex

        if isCorrect {
            correctCount += 1
        }

        let xp = isCorrect ? GamificationService.XP.quizCorrect : 0
        totalXPEarned += xp

        gamification.recordQuizAnswer(
            wordId: question.grammarId ?? UUID(),
            word: question.pattern,
            quizType: question.quizType.rawValue,
            isCorrect: isCorrect
        )
    }

    func nextQuestion() {
        currentIndex += 1
        selectedAnswer = nil
        isAnswered = false

        if currentIndex >= questions.count {
            isFinished = true
        }
    }

    // MARK: - Private

    private func makeQuestion(item: SavedGrammar, type: GrammarQuizType, allItems: [SavedGrammar]) -> GrammarQuizQuestion {
        let distractors = allItems
            .filter { $0.pattern != item.pattern }
            .shuffled()
            .prefix(3)

        let correctIndex = Int.random(in: 0...3)

        var options: [String]
        switch type {
        case .patternToExplanation:
            options = distractors.map { $0.explanation }
            options.insert(item.explanation, at: correctIndex)
        case .explanationToPattern:
            options = distractors.map { $0.pattern }
            options.insert(item.pattern, at: correctIndex)
        }

        return GrammarQuizQuestion(
            pattern: item.pattern,
            explanation: item.explanation,
            example: item.example,
            grammarId: item.id,
            quizType: type,
            options: options,
            correctIndex: correctIndex
        )
    }
}
