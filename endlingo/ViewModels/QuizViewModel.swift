import Foundation

enum QuizType: String {
    case enToKo = "en_to_ko"
    case koToEn = "ko_to_en"
}

struct QuizQuestion {
    let word: SavedWord
    let quizType: QuizType
    let options: [String]
    let correctIndex: Int
}

@Observable
@MainActor
final class QuizViewModel {
    var questions: [QuizQuestion] = []
    var currentIndex = 0
    var selectedAnswer: Int?
    var isAnswered = false
    var isFinished = false
    var correctCount = 0
    var totalXPEarned = 0

    private let gamification = GamificationService.shared

    var currentQuestion: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        questions.isEmpty ? 0 : Double(currentIndex) / Double(questions.count)
    }

    var canStartQuiz: Bool {
        VocabularyService.shared.words.filter { $0.meaning != nil }.count >= 4
    }

    func generateQuiz(type: QuizType, count: Int = 10) {
        let words = VocabularyService.shared.words.filter { $0.meaning != nil }
        guard words.count >= 4 else { return }

        let selected = Array(words.shuffled().prefix(min(count, words.count)))
        questions = selected.map { word in
            makeQuestion(word: word, type: type, allWords: words)
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
            wordId: question.word.id,
            word: question.word.word,
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

    private func makeQuestion(word: SavedWord, type: QuizType, allWords: [SavedWord]) -> QuizQuestion {
        let distractors = allWords
            .filter { $0.id != word.id }
            .shuffled()
            .prefix(3)

        let correctIndex = Int.random(in: 0...3)

        var options: [String]
        switch type {
        case .enToKo:
            options = distractors.map { $0.meaning ?? "" }
            options.insert(word.meaning ?? "", at: correctIndex)
        case .koToEn:
            options = distractors.map { $0.word }
            options.insert(word.word, at: correctIndex)
        }

        return QuizQuestion(
            word: word,
            quizType: type,
            options: options,
            correctIndex: correctIndex
        )
    }
}
