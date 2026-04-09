import Foundation
import AuthenticationServices
import CryptoKit
import GoogleSignIn
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

    // MARK: - 마지막 로그인 방법

    enum LoginMethod: String {
        case email, apple, google
    }

    /// 마지막 로그인 방법 (로그아웃 후에도 유지)
    static var lastLoginMethod: LoginMethod? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "lastLoginMethod") else { return nil }
            return LoginMethod(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: "lastLoginMethod")
        }
    }

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

    enum SignUpResult {
        case loggedIn        // 즉시 로그인 성공
        case confirmEmail    // 확인 메일 발송됨
        case alreadyExists   // 이미 등록된 이메일
    }

    /// 회원가입
    @discardableResult
    func signUp(email: String, password: String) async throws -> SignUpResult {
        let response = try await client.auth.signUp(email: email, password: password)
        if response.session != nil {
            currentUser = response.user
            isLoggedIn = true
            UserDefaults.standard.set(true, forKey: "hasAccount")
            Self.lastLoginMethod = .email
            return .loggedIn
        }
        // identities가 빈 배열이면 이미 등록된 이메일
        if response.user.identities?.isEmpty == true {
            return .alreadyExists
        }
        return .confirmEmail
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        currentUser = session.user
        isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "hasAccount")
        Self.lastLoginMethod = .email
        async let v: () = VocabularyService.shared.syncAfterLogin()
        async let g: () = GrammarService.shared.syncAfterLogin()
        _ = await (v, g)
        await GamificationService.shared.syncAfterLogin()
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    /// 비밀번호 변경: 현재 비밀번호 확인 후 새 비밀번호로 업데이트
    func changePassword(currentPassword: String, newPassword: String) async throws {
        // 현재 비밀번호 확인 (재로그인)
        guard let email = currentUser?.email else {
            throw ChangePasswordError.notLoggedIn
        }
        _ = try await client.auth.signIn(email: email, password: currentPassword)

        // 새 비밀번호로 업데이트
        _ = try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    enum ChangePasswordError: LocalizedError {
        case notLoggedIn

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return String(localized: "로그인 상태가 아닙니다")
            }
        }
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

    // MARK: - Apple Sign In

    /// Apple 로그인용 nonce (CSRF 방지)
    private(set) var currentNonce: String?

    /// 랜덤 nonce 생성
    func generateNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return nonce
    }

    /// Apple ID Token으로 Supabase 로그인
    func signInWithApple(idToken: String, nonce: String) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        currentUser = session.user
        isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "hasAccount")
        Self.lastLoginMethod = .apple
        async let v: () = VocabularyService.shared.syncAfterLogin()
        async let g: () = GrammarService.shared.syncAfterLogin()
        _ = await (v, g)
        await GamificationService.shared.syncAfterLogin()
    }

    /// SHA256 해시 (Apple Sign In 요구사항)
    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(errorCode == errSecSuccess)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    // MARK: - Google Sign In

    /// Google 로그인 (GoogleSignIn SDK → Supabase ID Token)
    func signInWithGoogle() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController
        else {
            throw GoogleSignInError.noRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleSignInError.noIdToken
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken)
        )
        currentUser = session.user
        isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "hasAccount")
        Self.lastLoginMethod = .google
        async let v: () = VocabularyService.shared.syncAfterLogin()
        async let g: () = GrammarService.shared.syncAfterLogin()
        _ = await (v, g)
        await GamificationService.shared.syncAfterLogin()
    }

    /// Google Sign In URL 처리
    func handleGoogleSignInURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    enum GoogleSignInError: LocalizedError {
        case noRootViewController
        case noIdToken

        var errorDescription: String? {
            switch self {
            case .noRootViewController:
                return String(localized: "화면을 찾을 수 없습니다")
            case .noIdToken:
                return String(localized: "Google 로그인 정보를 가져올 수 없습니다")
            }
        }
    }

    // MARK: - Deep Link

    func handleDeepLink(url: URL) async {
        do {
            let session = try await client.auth.session(from: url)
            currentUser = session.user
            isLoggedIn = true
            async let v: () = VocabularyService.shared.syncAfterLogin()
            async let g: () = GrammarService.shared.syncAfterLogin()
            _ = await (v, g)
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
            async let v: () = VocabularyService.shared.syncAfterLogin()
            async let g: () = GrammarService.shared.syncAfterLogin()
            _ = await (v, g)
            await GamificationService.shared.syncAfterLogin()
        } catch {
            // No stored session
        }
    }
}
