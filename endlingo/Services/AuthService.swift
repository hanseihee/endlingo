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
            return true
        }
        return false
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        currentUser = session.user
        isLoggedIn = true
        await VocabularyService.shared.syncAfterLogin()
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    func deleteAccount() async {
        do {
            let session = try await client.auth.session
            var request = URLRequest(url: URL(string: "\(SupabaseConfig.functionsBaseURL)/delete-account")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("Delete account response: \(statusCode) \(String(data: data, encoding: .utf8) ?? "")")
            if statusCode == 200 {
                try? await client.auth.signOut()
                currentUser = nil
                isLoggedIn = false
                VocabularyService.shared.clearAfterLogout()
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
        let message = error.localizedDescription.lowercased()
        if message.contains("email not confirmed") || message.contains("email_not_confirmed") {
            return "이메일 인증이 완료되지 않았습니다. 메일함을 확인해주세요."
        } else if message.contains("invalid login") || message.contains("invalid_credentials") {
            return "이메일 또는 비밀번호가 올바르지 않습니다"
        } else if message.contains("already registered") || message.contains("already been registered") {
            return "이미 등록된 이메일입니다. 로그인해주세요"
        } else if message.contains("email") && message.contains("valid") {
            return "올바른 이메일 형식을 입력해주세요"
        } else if message.contains("password") {
            return "비밀번호는 6자 이상이어야 합니다"
        }
        return "오류가 발생했습니다. 다시 시도해주세요"
    }

    // MARK: - Session

    private func restoreSession() async {
        defer { isLoading = false }
        do {
            let session = try await client.auth.session
            currentUser = session.user
            isLoggedIn = true
            await VocabularyService.shared.syncAfterLogin()
        } catch {
            // No stored session
        }
    }
}
