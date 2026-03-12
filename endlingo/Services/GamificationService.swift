import Foundation

@Observable
@MainActor
final class GamificationService {
    static let shared = GamificationService()

    private(set) var stats = UserStats()
    private(set) var learningRecords: [LearningRecord] = []
    private(set) var quizResults: [QuizResult] = []
    private(set) var earnedBadges: [EarnedBadge] = []
    private(set) var newBadge: BadgeType?

    // MARK: - XP Rewards

    enum XP {
        static let lessonView = 10
        static let wordSave = 5
        static let quizCorrect = 3
    }

    private var streakMultiplier: Int {
        stats.currentStreak >= 7 ? 2 : 1
    }

    // MARK: - Private

    private var auth: AuthService { AuthService.shared }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let recordsFileURL: URL
    private let quizFileURL: URL
    private let badgesFileURL: URL
    private let statsFileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordsFileURL = docs.appendingPathComponent("learning_records.json")
        quizFileURL = docs.appendingPathComponent("quiz_results.json")
        badgesFileURL = docs.appendingPathComponent("earned_badges.json")
        statsFileURL = docs.appendingPathComponent("user_stats.json")
        loadLocal()
        recalculateStats()
    }

    // MARK: - Public API

    /// 레슨 열람 시 호출 (하루 1회만 XP 지급)
    func recordLessonView(level: String, environment: String) {
        let today = SupabaseConfig.todayDateString
        guard !learningRecords.contains(where: { $0.date == today }) else { return }

        let xp = XP.lessonView * streakMultiplier
        let record = LearningRecord(
            id: UUID(), userId: auth.userId,
            date: today, level: level, environment: environment,
            xpEarned: xp, createdAt: Date()
        )

        learningRecords.append(record)

        if auth.isLoggedIn {
            Task { await remoteInsert(record, table: "learning_records") }
        } else {
            persistLocal(learningRecords, to: recordsFileURL)
        }

        stats.totalXP += xp
        recalculateStats()
        checkBadges()
    }

    /// 단어 저장 시 XP 지급
    func awardWordSaveXP() {
        let xp = XP.wordSave * streakMultiplier
        stats.totalXP += xp
        stats.recalculateLevel()
        persistStats()
        checkBadges()
    }

    /// 퀴즈 답변 기록
    func recordQuizAnswer(wordId: UUID, word: String, quizType: String, isCorrect: Bool) {
        let xp = isCorrect ? XP.quizCorrect * streakMultiplier : 0
        let result = QuizResult(
            id: UUID(), userId: auth.userId,
            date: SupabaseConfig.todayDateString, quizType: quizType,
            wordId: wordId, word: word,
            isCorrect: isCorrect, xpEarned: xp, createdAt: Date()
        )

        quizResults.append(result)

        if auth.isLoggedIn {
            Task { await remoteInsert(result, table: "quiz_results") }
        } else {
            persistLocal(quizResults, to: quizFileURL)
        }

        stats.totalXP += xp
        stats.totalQuizzes += 1
        if isCorrect { stats.correctQuizzes += 1 }
        stats.recalculateLevel()
        persistStats()
        checkBadges()
    }

    /// 캘린더용: 특정 달의 학습 날짜 → XP 맵
    func xpByDate(year: Int, month: Int) -> [String: Int] {
        let prefix = String(format: "%04d-%02d", year, month)
        var map: [String: Int] = [:]
        for record in learningRecords where record.date.hasPrefix(prefix) {
            map[record.date, default: 0] += record.xpEarned
        }
        // 퀴즈 XP도 합산
        for result in quizResults where result.date.hasPrefix(prefix) {
            map[result.date, default: 0] += result.xpEarned
        }
        return map
    }

    /// 배지 획득 알림 초기화
    func dismissNewBadge() {
        newBadge = nil
    }

    // MARK: - Sync

    func syncAfterLogin() async {
        guard let userId = auth.userId else { return }

        // 로컬 데이터 업로드
        let localRecords = loadLocalArray(from: recordsFileURL, as: LearningRecord.self)
        for record in localRecords {
            let updated = LearningRecord(
                id: record.id, userId: userId,
                date: record.date, level: record.level,
                environment: record.environment,
                xpEarned: record.xpEarned, createdAt: record.createdAt
            )
            await remoteInsert(updated, table: "learning_records")
        }

        let localQuiz = loadLocalArray(from: quizFileURL, as: QuizResult.self)
        for result in localQuiz {
            let updated = QuizResult(
                id: result.id, userId: userId,
                date: result.date, quizType: result.quizType,
                wordId: result.wordId, word: result.word,
                isCorrect: result.isCorrect, xpEarned: result.xpEarned,
                createdAt: result.createdAt
            )
            await remoteInsert(updated, table: "quiz_results")
        }

        let localBadges = loadLocalArray(from: badgesFileURL, as: EarnedBadge.self)
        for badge in localBadges {
            let updated = EarnedBadge(
                id: badge.id, userId: userId,
                badgeType: badge.badgeType, earnedAt: badge.earnedAt
            )
            await remoteInsert(updated, table: "earned_badges")
        }

        // 로컬 파일 정리
        if !localRecords.isEmpty { try? FileManager.default.removeItem(at: recordsFileURL) }
        if !localQuiz.isEmpty { try? FileManager.default.removeItem(at: quizFileURL) }
        if !localBadges.isEmpty { try? FileManager.default.removeItem(at: badgesFileURL) }
        try? FileManager.default.removeItem(at: statsFileURL)

        // 서버에서 전체 로드
        await fetchRemote()
        recalculateStats()
    }

    func clearAfterLogout() {
        learningRecords = []
        quizResults = []
        earnedBadges = []
        stats = UserStats()
    }

    // MARK: - Streak Calculation

    private func recalculateStats() {
        // 스트릭 계산
        let dates = Set(learningRecords.map { $0.date }).sorted().reversed()
        var streak = 0
        let calendar = Calendar.current
        let kstTZ = TimeZone(identifier: "Asia/Seoul")!

        var checkDate = {
            var cal = Calendar.current
            cal.timeZone = kstTZ
            return cal.startOfDay(for: Date())
        }()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = kstTZ

        let todayStr = formatter.string(from: checkDate)

        // 오늘 학습 안 했으면 어제부터 체크
        if !dates.contains(todayStr) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        for _ in 0..<365 {
            let dateStr = formatter.string(from: checkDate)
            if dates.contains(dateStr) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        stats.currentStreak = streak
        stats.bestStreak = max(stats.bestStreak, streak)
        stats.totalLearningDays = Set(learningRecords.map { $0.date }).count

        // XP 재계산
        let recordXP = learningRecords.reduce(0) { $0 + $1.xpEarned }
        let quizXP = quizResults.reduce(0) { $0 + $1.xpEarned }
        let wordXP = VocabularyService.shared.words.count * XP.wordSave
        stats.totalXP = recordXP + quizXP + wordXP

        stats.totalQuizzes = quizResults.count
        stats.correctQuizzes = quizResults.filter { $0.isCorrect }.count
        stats.recalculateLevel()

        persistStats()
    }

    // MARK: - Badge Checking

    private func checkBadges() {
        let earned = Set(earnedBadges.map { $0.badgeType })
        let wordCount = VocabularyService.shared.words.count

        let checks: [(BadgeType, Bool)] = [
            (.firstStep, !learningRecords.isEmpty),
            (.wordCollector50, wordCount >= 50),
            (.wordCollector100, wordCount >= 100),
            (.sevenDayStreak, stats.bestStreak >= 7),
            (.thirtyDayStreak, stats.bestStreak >= 30),
            (.quizMaster, stats.quizAccuracy >= 90 && stats.totalQuizzes >= 20),
            (.quizEnthusiast, stats.totalQuizzes >= 100),
        ]

        for (badge, unlocked) in checks {
            guard unlocked, !earned.contains(badge.rawValue) else { continue }

            let entry = EarnedBadge(
                id: UUID(), userId: auth.userId,
                badgeType: badge.rawValue, earnedAt: Date()
            )
            earnedBadges.append(entry)
            newBadge = badge

            if auth.isLoggedIn {
                Task { await remoteInsert(entry, table: "earned_badges") }
            } else {
                persistLocal(earnedBadges, to: badgesFileURL)
            }
        }
    }

    // MARK: - Remote (Supabase)

    private func remoteInsert<T: Encodable>(_ item: T, table: String) async {
        guard let token = await auth.accessToken,
              let url = URL(string: "\(SupabaseConfig.restBaseURL)/\(table)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? encoder.encode(item)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("Insert \(table) error: \(http.statusCode)")
            }
        } catch {
            print("Insert \(table) error: \(error)")
        }
    }

    private func fetchRemote() async {
        guard let token = await auth.accessToken else { return }

        async let records: [LearningRecord] = fetchTable("learning_records", token: token)
        async let quiz: [QuizResult] = fetchTable("quiz_results", token: token)
        async let badges: [EarnedBadge] = fetchTable("earned_badges", token: token)

        learningRecords = await records
        quizResults = await quiz
        earnedBadges = await badges
    }

    private func fetchTable<T: Decodable>(_ table: String, token: String) async -> [T] {
        guard let url = URL(string: "\(SupabaseConfig.restBaseURL)/\(table)?select=*&order=created_at.desc") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try decoder.decode([T].self, from: data)
        } catch {
            print("Fetch \(table) error: \(error)")
            return []
        }
    }

    // MARK: - Local Storage

    private func loadLocal() {
        learningRecords = loadLocalArray(from: recordsFileURL, as: LearningRecord.self)
        quizResults = loadLocalArray(from: quizFileURL, as: QuizResult.self)
        earnedBadges = loadLocalArray(from: badgesFileURL, as: EarnedBadge.self)

        if let data = try? Data(contentsOf: statsFileURL),
           let saved = try? decoder.decode(UserStats.self, from: data) {
            stats = saved
        }
    }

    private func loadLocalArray<T: Decodable>(from url: URL, as type: T.Type) -> [T] {
        guard let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([T].self, from: data) else { return [] }
        return items
    }

    private func persistLocal<T: Encodable>(_ items: T, to url: URL) {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func persistStats() {
        persistLocal(stats, to: statsFileURL)
    }
}
