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
            supabaseURL: URL(string: "https://alvawqinuacabfnqduoy.supabase.co")!,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsdmF3cWludWFjYWJmbnFkdW95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNjExNDgsImV4cCI6MjA4ODgzNzE0OH0.C-gnavFBHa-gIyvoGngaYfV6htDTiFyOmj5MemIlzhY",
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
            var request = URLRequest(url: URL(string: "https://alvawqinuacabfnqduoy.supabase.co/functions/v1/delete-account")!)
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
