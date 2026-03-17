import Foundation
import Supabase
import Auth

@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    let client: SupabaseClient

    private(set) var currentUser: User?
    private(set) var isLoggedIn = false
    private(set) var isLoading = true

    var isGuest: Bool {
        !isLoggedIn && UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    var userEmail: String? {
        currentUser?.email
    }

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.anonKey,
            options: .init(auth: .init(flowType: .implicit, emitLocalSessionAsInitialSession: true))
        )

        Task { await restoreSession() }
    }

    // MARK: - Email Auth

    /// 회원가입. 이메일 확인이 필요하면 false, 즉시 로그인되면 true 반환
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password)
        if response.session != nil {
            currentUser = response.user
            isLoggedIn = true
            UserDefaults.standard.set(true, forKey: "hasAccount")
            return true
        }
        return false
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        currentUser = session.user
        isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "hasAccount")
        async let v: () = VocabularyService.shared.syncAfterLogin()
        async let g: () = GrammarService.shared.syncAfterLogin()
        async let ga: () = GamificationService.shared.syncAfterLogin()
        _ = await (v, g, ga)
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    func deleteAccount() async {
        do {
            let session = try await client.auth.session
            guard let url = URL(string: "\(SupabaseConfig.functionsBaseURL)/delete-account") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("Delete account response: \(statusCode) \(String(data: data, encoding: .utf8) ?? "")")
            if statusCode == 200 {
                try? await client.auth.signOut()
                currentUser = nil
                isLoggedIn = false
                UserDefaults.standard.removeObject(forKey: "hasAccount")
                VocabularyService.shared.clearAfterLogout()
                GrammarService.shared.clearAfterLogout()
                GamificationService.shared.clearAfterLogout()
                NotificationService.shared.cancelAll()
                resetUserData()
            }
        } catch {
            print("Delete account error: \(error)")
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("Sign out error: \(error)")
        }
        currentUser = nil
        isLoggedIn = false
        VocabularyService.shared.clearAfterLogout()
        GrammarService.shared.clearAfterLogout()
        GamificationService.shared.clearAfterLogout()
        NotificationService.shared.cancelAll()
        resetUserData()
    }

    // MARK: - Deep Link

    func handleDeepLink(url: URL) async {
        do {
            let session = try await client.auth.session(from: url)
            currentUser = session.user
            isLoggedIn = true
            await VocabularyService.shared.syncAfterLogin()
            await GrammarService.shared.syncAfterLogin()
            await GamificationService.shared.syncAfterLogin()
        } catch {
            print("Deep link error: \(error)")
        }
    }

    var userId: UUID? {
        currentUser?.id
    }

    var accessToken: String? {
        get async {
            try? await client.auth.session.accessToken
        }
    }

    // MARK: - Reset

    private func resetUserData() {
        let keys = [
            "hasCompletedOnboarding",
            "selectedLevel",
            "selectedEnvironment",
            "notificationHour",
            "notificationMinute"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Error Parsing

    static func parseAuthError(_ error: Error) -> String {
        let message = "\(error)".lowercased()
        let desc = error.localizedDescription.lowercased()
        let combined = message + " " + desc
        print("[Auth] Error: \(error)")

        if combined.contains("email not confirmed") || combined.contains("email_not_confirmed") {
            return String(localized: "이메일 인증이 완료되지 않았습니다. 메일함을 확인해주세요.")
        } else if combined.contains("invalid login") || combined.contains("invalid_credentials") {
            return String(localized: "이메일 또는 비밀번호가 올바르지 않습니다")
        } else if combined.contains("already registered") || combined.contains("already been registered") || combined.contains("user_already_exists") {
            return String(localized: "이미 등록된 이메일입니다. 로그인해주세요")
        } else if combined.contains("rate limit") || combined.contains("too many requests") || combined.contains("over_request_rate_limit") || combined.contains("over_email_send_rate_limit") {
            return String(localized: "요청이 너무 많습니다. 잠시 후 다시 시도해주세요")
        } else if combined.contains("network") || combined.contains("internet") || combined.contains("offline") || combined.contains("urlsessiontask") {
            return String(localized: "네트워크 연결을 확인해주세요")
        } else if combined.contains("email") && combined.contains("valid") {
            return String(localized: "올바른 이메일 형식을 입력해주세요")
        } else if combined.contains("password") && (combined.contains("short") || combined.contains("least")) {
            return String(localized: "비밀번호는 6자 이상이어야 합니다")
        } else if combined.contains("signup_disabled") {
            return String(localized: "현재 회원가입이 비활성화되어 있습니다")
        }
        return String(localized: "오류가 발생했습니다. 다시 시도해주세요")
    }

    // MARK: - Session

    private func restoreSession() async {
        defer { isLoading = false }
        do {
            let session = try await client.auth.session
            currentUser = session.user
            isLoggedIn = true
            await VocabularyService.shared.syncAfterLogin()
            await GrammarService.shared.syncAfterLogin()
            await GamificationService.shared.syncAfterLogin()
        } catch {
            // No stored session
        }
    }
}
