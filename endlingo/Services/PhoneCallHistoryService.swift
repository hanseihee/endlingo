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
    // TEMP: 오디오 파이프라인 디버깅용 상향. 정식 배포 전 10으로 복원 필요.
    static let dailyCallLimit = 999

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
    /// `personaNameOverride`를 주면 variant에서 확정된 이름(예: "Priya")을 기록. nil이면 시나리오 대표 이름.
    func record(
        id: UUID = UUID(),
        scenario: PhoneCallScenario,
        personaNameOverride: String? = nil,
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
            personaName: personaNameOverride ?? scenario.personaName,
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

    /// Edge Function이 pending으로 만들어둔 row를 완성시킵니다.
    /// 로그인 사용자 전용. 서버 UPDATE가 완료되면 로컬 records 배열에도 반영.
    /// `personaNameOverride`를 주면 variant에서 확정된 이름으로 기록.
    func complete(
        sessionId: UUID,
        scenario: PhoneCallScenario,
        personaNameOverride: String? = nil,
        durationSeconds: Int,
        transcript: [PhoneCallRecord.TranscriptLine],
        startedAt: Date
    ) {
        guard auth.isLoggedIn,
              let userUUID = auth.userId else { return }

        let record = PhoneCallRecord(
            id: sessionId,
            userId: userUUID,
            scenarioId: scenario.id,
            scenarioTitle: scenario.title,
            personaName: personaNameOverride ?? scenario.personaName,
            personaEmoji: scenario.emoji,
            durationSeconds: durationSeconds,
            transcript: transcript,
            startedAt: startedAt,
            createdAt: Date(),
            reviewIssues: nil
        )

        // 메모리 반영 (insert 혹은 기존 placeholder 덮어쓰기)
        if let idx = records.firstIndex(where: { $0.id == sessionId }) {
            records[idx] = record
        } else {
            records.insert(record, at: 0)
        }

        Task {
            guard let token = await auth.accessToken else { return }
            let payload: [String: Any] = [
                "duration_seconds": durationSeconds,
                "transcript": transcript.map { line -> [String: Any] in
                    var dict: [String: Any] = ["speaker": line.speaker, "text": line.text]
                    if let t = line.translation { dict["translation"] = t }
                    return dict
                },
                "status": "completed",
                "completed_at": ISO8601DateFormatter().string(from: Date()),
            ]
            await Self.updateSession(id: sessionId, payload: payload, token: token)
        }
    }

    /// 통화 후 생성된 영작 피드백을 기존 session row에 저장.
    func updateReview(sessionId: UUID, issues: [CallReviewIssue]) {
        guard auth.isLoggedIn else { return }

        if let idx = records.firstIndex(where: { $0.id == sessionId }) {
            records[idx].reviewIssues = issues
        }

        Task {
            guard let token = await auth.accessToken else { return }
            let issuesJson = issues.map { issue in
                [
                    "original": issue.original,
                    "improved": issue.improved,
                    "explanation": issue.explanation,
                ]
            }
            let payload: [String: Any] = ["review_issues": issuesJson]
            await Self.updateSession(id: sessionId, payload: payload, token: token)
        }
    }

    /// Supabase REST PATCH 헬퍼.
    private static func updateSession(id: UUID, payload: [String: Any], token: String) async {
        guard let url = URL(string: "\(SupabaseConfig.restBaseURL)/phone_call_sessions?id=eq.\(id.uuidString)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
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
    /// 로그인 사용자는 서버가 진실의 원천이므로 remote가 빈 배열이어도
    /// 무조건 덮어써서 서버 측 삭제/초기화가 즉시 반영되게 함.
    func refreshFromServer() async {
        guard auth.isLoggedIn else {
            print("[PhoneCallHistory] refresh skipped — not logged in")
            return
        }
        guard let token = await auth.accessToken else {
            print("[PhoneCallHistory] refresh skipped — no access token")
            return
        }
        let before = records.count
        let remote: [PhoneCallRecord] = await SupabaseAPI.fetch(
            "phone_call_sessions",
            query: "select=*&order=started_at.desc",
            token: token
        )
        records = remote
        // 예전 게스트 세션의 잔존 파일이 있으면 정리 (todayCallCount 불일치 방지)
        try? FileManager.default.removeItem(at: fileURL)
        print("[PhoneCallHistory] refreshed — remote=\(remote.count), local before=\(before), today=\(todayCallCount), remaining=\(remainingTodayCallCount)")
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
