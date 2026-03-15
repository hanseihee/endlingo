import Foundation

enum QuizType: String {
    case enToKo = "en_to_ko"
    case koToEn = "ko_to_en"
}

enum QuizWordSource: String, CaseIterable {
    case saved = "저장한 단어"
    case builtin = "필수 영단어"
    case mixed = "전체"
}

struct QuizQuestion {
    let wordText: String
    let meaningText: String
    let wordId: UUID?
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

    // MARK: - 외운 단어 관리

    private static let masteredKey = "masteredWords"

    private(set) var masteredWords: Set<String> = {
        let array = UserDefaults.standard.stringArray(forKey: masteredKey) ?? []
        return Set(array)
    }()

    var masteredCount: Int { masteredWords.count }

    func isMastered(_ word: String) -> Bool {
        masteredWords.contains(word.lowercased())
    }

    func toggleMastered(_ word: String) {
        let key = word.lowercased()
        if masteredWords.contains(key) {
            masteredWords.remove(key)
        } else {
            masteredWords.insert(key)
        }
        UserDefaults.standard.set(Array(masteredWords), forKey: Self.masteredKey)
    }

    var currentQuestion: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var progress: Double {
        questions.isEmpty ? 0 : Double(currentIndex) / Double(questions.count)
    }

    func canStartQuiz(source: QuizWordSource) -> Bool {
        switch source {
        case .saved:
            return VocabularyService.shared.words.filter { $0.meaning != nil }.count >= 5
        case .builtin:
            return BuiltInWordBank.shared.isLoaded
        case .mixed:
            let savedCount = VocabularyService.shared.words.filter { $0.meaning != nil }.count
            let builtinCount = BuiltInWordBank.shared.words.count
            return savedCount + builtinCount >= 5
        }
    }

    func generateQuiz(type: QuizType, source: QuizWordSource, count: Int = 10) {
        let pool = buildWordPool(source: source)
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
        AnalyticsService.logQuizStart(type: type.rawValue, source: source.rawValue)
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
            wordId: question.wordId ?? UUID(),
            word: question.wordText,
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
            AnalyticsService.logQuizComplete(
                type: questions.first?.quizType.rawValue ?? "",
                correct: correctCount,
                total: questions.count,
                xp: totalXPEarned
            )
        }
    }

    // MARK: - Private

    private struct WordItem {
        let word: String
        let meaning: String
        let id: UUID?
    }

    private func buildWordPool(source: QuizWordSource) -> [WordItem] {
        var pool: [WordItem] = []

        if source == .saved || source == .mixed {
            let saved = VocabularyService.shared.words
                .filter { $0.meaning != nil }
                .map { WordItem(word: $0.word, meaning: $0.meaning!, id: $0.id) }
            pool.append(contentsOf: saved)
        }

        if source == .builtin || source == .mixed {
            let builtin = BuiltInWordBank.shared.words
                .map { WordItem(word: $0.word, meaning: $0.meaning, id: nil) }
            pool.append(contentsOf: builtin)
        }

        // 외운 단어 제외
        pool = pool.filter { !masteredWords.contains($0.word.lowercased()) }

        return pool
    }

    private func makeQuestion(item: WordItem, type: QuizType, allItems: [WordItem]) -> QuizQuestion {
        let distractors = allItems
            .filter { $0.word != item.word }
            .shuffled()
            .prefix(3)

        let correctIndex = Int.random(in: 0...3)

        var options: [String]
        switch type {
        case .enToKo:
            options = distractors.map { $0.meaning }
            options.insert(item.meaning, at: correctIndex)
        case .koToEn:
            options = distractors.map { $0.word }
            options.insert(item.word, at: correctIndex)
        }

        return QuizQuestion(
            wordText: item.word,
            meaningText: item.meaning,
            wordId: item.id,
            quizType: type,
            options: options,
            correctIndex: correctIndex
        )
    }
}
