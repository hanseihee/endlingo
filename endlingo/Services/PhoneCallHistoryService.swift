import Foundation

/// AI 전화영어 통화 기록 저장소.
/// VocabularyService와 동일한 로컬 우선 + 서버 동기화 패턴을 따릅니다.
///
/// - 게스트: `Documents/phone_call_history.json`
/// - 로그인: Supabase `phone_call_sessions` 테이블
/// - 로그인 시점에 로컬 기록을 서버로 업로드하고 로컬 파일을 정리합니다.
@Observable
@MainActor
final class PhoneCallHistoryService {
    static let shared = PhoneCallHistoryService()

    /// 로그인 사용자당 일일 통화 한도.
    /// Edge Function `realtime-session`의 `DAILY_LIMIT`과 일치해야 합니다.
    /// 두 값을 변경할 때는 함께 조정하고 Edge Function을 재배포하세요.
    static let dailyCallLimit = 10

    private(set) var records: [PhoneCallRecord] = []

    private let fileURL: URL
    private var auth: AuthService { AuthService.shared }

    /// 오늘(UTC 00:00 기준) 사용한 통화 수. Edge Function의 카운트와 동일 기준.
    var todayCallCount: Int {
        let todayStart = Self.todayStartUTC
        return records.filter { $0.startedAt >= todayStart }.count
    }

    /// 남은 통화 가능 횟수.
    var remainingTodayCallCount: Int {
        max(0, Self.dailyCallLimit - todayCallCount)
    }

    private static var todayStartUTC: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.startOfDay(for: Date())
    }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("phone_call_history.json")
        loadLocal()
    }

    // MARK: - Public API

    /// 통화 기록을 저장합니다. 동일 `id`가 이미 있으면 무시됩니다.
    func record(
        id: UUID = UUID(),
        scenario: PhoneCallScenario,
        durationSeconds: Int,
        transcript: [PhoneCallRecord.TranscriptLine],
        startedAt: Date
    ) {
        guard !records.contains(where: { $0.id == id }) else { return }

        let entry = PhoneCallRecord(
            id: id,
            userId: auth.userId,
            scenarioId: scenario.id,
            scenarioTitle: scenario.title,
            personaName: scenario.personaName,
            personaEmoji: scenario.emoji,
            durationSeconds: durationSeconds,
            transcript: transcript,
            startedAt: startedAt,
            createdAt: Date()
        )

        records.insert(entry, at: 0)

        if auth.isLoggedIn {
            Task {
                guard let token = await auth.accessToken else { return }
                await SupabaseAPI.insert(entry, table: "phone_call_sessions", token: token)
            }
        } else {
            persistLocal()
        }
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }

        if auth.isLoggedIn {
            Task {
                guard let token = await auth.accessToken else { return }
                await SupabaseAPI.delete(
                    "phone_call_sessions",
                    filter: "id=eq.\(id.uuidString)",
                    token: token
                )
            }
        } else {
            persistLocal()
        }
    }

    /// 로그인 시 호출: 로컬 기록을 서버에 업로드 후 서버에서 최신 리스트 로드.
    func syncAfterLogin() async {
        guard let token = await auth.accessToken,
              let userUUID = auth.userId else { return }

        let local = loadLocalRecords()
        for record in local {
            let entry = PhoneCallRecord(
                id: record.id,
                userId: userUUID,
                scenarioId: record.scenarioId,
                scenarioTitle: record.scenarioTitle,
                personaName: record.personaName,
                personaEmoji: record.personaEmoji,
                durationSeconds: record.durationSeconds,
                transcript: record.transcript,
                startedAt: record.startedAt,
                createdAt: record.createdAt
            )
            await SupabaseAPI.insert(entry, table: "phone_call_sessions", token: token)
        }

        let remote: [PhoneCallRecord] = await SupabaseAPI.fetch(
            "phone_call_sessions",
            query: "select=*&order=started_at.desc",
            token: token
        )
        if !remote.isEmpty || local.isEmpty {
            records = remote
            if !local.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// 로그아웃 시 메모리 클리어 (로컬 파일은 남겨둠 — 다시 게스트 모드에서 활용).
    func clearAfterLogout() {
        records = []
        loadLocal()
    }

    /// 앱 시작 후 인증 복구 완료 시 서버에서 최신 리스트를 당겨옵니다.
    func refreshFromServer() async {
        guard auth.isLoggedIn,
              let token = await auth.accessToken else { return }
        let remote: [PhoneCallRecord] = await SupabaseAPI.fetch(
            "phone_call_sessions",
            query: "select=*&order=started_at.desc",
            token: token
        )
        if !remote.isEmpty {
            records = remote
        }
    }

    // MARK: - Local Storage

    private func loadLocal() {
        records = loadLocalRecords()
    }

    private func loadLocalRecords() -> [PhoneCallRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? SupabaseAPI.decoder.decode([PhoneCallRecord].self, from: data) else {
            return []
        }
        return loaded.sorted { $0.startedAt > $1.startedAt }
    }

    private func persistLocal() {
        guard let data = try? SupabaseAPI.encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
