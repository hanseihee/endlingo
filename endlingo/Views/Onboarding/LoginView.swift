import SwiftUI
import AuthenticationServices

// MARK: - Navigation 목적지

private enum AuthDestination: Hashable {
    case login
    case signUp
}

// MARK: - LoginView (Welcome 화면 + NavigationStack)

struct LoginView: View {
    let onLoginSuccess: () -> Void
    let onGuestLogin: () -> Void

    @State private var auth = AuthService.shared
    @State private var socialLoginError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // 앱 아이콘 & 타이틀
                VStack(spacing: 12) {
                    Image("MainCharacter")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)

                    Text("영어하자")
                        .font(.largeTitle.bold())

                    Text("매일 새로운 영어 문장으로\n실력을 키워보세요")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // 버튼 영역
                VStack(spacing: 12) {
                    // 로그인 / 회원가입 버튼 가로 배치
                    HStack(spacing: 12) {
                        NavigationLink(value: AuthDestination.login) {
                            Text("로그인")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        NavigationLink(value: AuthDestination.signUp) {
                            Text("회원가입")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .overlay(alignment: .leading) {
                        if AuthService.lastLoginMethod == .email {
                            LastUsedBadge()
                        }
                    }

                    // 구분선
                    HStack {
                        Rectangle().fill(Color(.separator)).frame(height: 0.5)
                        Text("또는")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Rectangle().fill(Color(.separator)).frame(height: 0.5)
                    }
                    .padding(.vertical, 4)

                    // 소셜 로그인
                    AppleSignInButton(onSuccess: onLoginSuccess, onError: { socialLoginError = $0 })
                        .frame(height: 52)
                        .overlay(alignment: .trailing) {
                            if AuthService.lastLoginMethod == .apple {
                                LastUsedBadge()
                            }
                        }

                    GoogleSignInButton(onSuccess: onLoginSuccess, onError: { socialLoginError = $0 })
                        .frame(height: 52)
                        .overlay(alignment: .trailing) {
                            if AuthService.lastLoginMethod == .google {
                                LastUsedBadge()
                            }
                        }

                    if let socialLoginError {
                        Text(socialLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    // 게스트 진입
                    Button {
                        onGuestLogin()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                            Text("게스트로 둘러보기")
                                .font(.body.weight(.medium))
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .navigationDestination(for: AuthDestination.self) { destination in
                AuthFormView(
                    initialMode: destination,
                    onLoginSuccess: onLoginSuccess
                )
            }
        }
    }
}

// MARK: - AuthFormView (로그인/회원가입 폼 — push로 진입)

private struct AuthFormView: View {
    let onLoginSuccess: () -> Void

    @State private var isLogin: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSuccessMessage = false
    @State private var showResetPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    @State private var auth = AuthService.shared
    @FocusState private var isEmailFocused: Bool

    init(initialMode: AuthDestination, onLoginSuccess: @escaping () -> Void) {
        self.onLoginSuccess = onLoginSuccess
        self._isLogin = State(initialValue: initialMode == .login)
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // 입력 필드
                VStack(spacing: 12) {
                    TextField("이메일", text: $email)
                        .focused($isEmailFocused)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("비밀번호 (6자 이상)", text: $password)
                        .textContentType(isLogin ? .password : .newPassword)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // 에러/성공 메시지
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(isSuccessMessage ? .green : .red)
                        .multilineTextAlignment(.center)
                }

                // 제출 버튼
                Button {
                    submit()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isLogin ? String(localized: "로그인") : String(localized: "회원가입"))
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isFormValid ? Color.accentColor : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!isFormValid || isLoading)

                // 로그인 모드: 비밀번호 찾기
                if isLogin {
                    Button {
                        resetEmail = email
                        resetSent = false
                        showResetPassword = true
                    } label: {
                        Text("비밀번호 찾기")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // 모드 전환 안내
                Button {
                    withAnimation {
                        isLogin.toggle()
                        errorMessage = nil
                    }
                } label: {
                    Text(isLogin
                         ? String(localized: "계정이 없으신가요? **회원가입**")
                         : String(localized: "이미 계정이 있으신가요? **로그인**"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isLogin ? String(localized: "로그인") : String(localized: "회원가입"))
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .alert("비밀번호 재설정", isPresented: $showResetPassword) {
            TextField("이메일", text: $resetEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            Button("전송") {
                let trimmed = resetEmail.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                Task {
                    try? await auth.resetPassword(email: trimmed)
                    await MainActor.run { resetSent = true }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("가입한 이메일을 입력하면\n비밀번호 재설정 링크를 보내드립니다")
        }
        .alert("메일 전송 완료", isPresented: $resetSent) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("비밀번호 재설정 링크가 이메일로 발송되었습니다. 메일함을 확인해주세요.")
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isEmailFocused = true
            }
        }
    }

    // MARK: - 제출

    private func submit() {
        guard isFormValid else { return }
        isLoading = true
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                if !isLogin {
                    let result = try await auth.signUp(email: trimmedEmail, password: password)
                    await MainActor.run {
                        switch result {
                        case .loggedIn:
                            onLoginSuccess()
                        case .confirmEmail:
                            isSuccessMessage = true
                            errorMessage = String(localized: "확인 메일을 발송했습니다. 이메일의 링크를 클릭한 후 로그인해주세요.")
                            isLogin = true
                            isLoading = false
                        case .alreadyExists:
                            isSuccessMessage = false
                            errorMessage = String(localized: "이미 등록된 이메일입니다. 로그인해주세요")
                            isLogin = true
                            isLoading = false
                        }
                    }
                } else {
                    try await auth.signIn(email: trimmedEmail, password: password)
                    await MainActor.run { onLoginSuccess() }
                }
            } catch {
                await MainActor.run {
                    isSuccessMessage = false
                    errorMessage = AuthService.parseAuthError(error)
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - 마지막 로그인 방법 배지

struct LastUsedBadge: View {
    var body: some View {
        Text("최근 사용")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .offset(x: 0, y: -30)
    }
}

// MARK: - Google Sign In 버튼 (재사용 컴포넌트)

struct GoogleSignInButton: View {
    let onSuccess: () -> Void
    let onError: (String) -> Void

    @State private var auth = AuthService.shared
    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            isLoading = true
            Task {
                do {
                    try await auth.signInWithGoogle()
                    await MainActor.run {
                        isLoading = false
                        onSuccess()
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        // 사용자가 취소한 경우 에러 표시하지 않음
                        if (error as NSError).code == -5 { return } // GIDSignInError.canceled
                        onError(AuthService.parseAuthError(error))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Image("GoogleLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("Google로 로그인")
                        .font(.body.weight(.medium))
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Apple Sign In 버튼 (재사용 컴포넌트)

struct AppleSignInButton: View {
    let onSuccess: () -> Void
    let onError: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var auth = AuthService.shared

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = auth.generateNonce()
            request.requestedScopes = [.email, .fullName]
            request.nonce = AuthService.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let identityTokenData = credential.identityToken,
                      let idToken = String(data: identityTokenData, encoding: .utf8)
                else {
                    onError(String(localized: "Apple 로그인 정보를 가져올 수 없습니다"))
                    return
                }
                guard let nonce = auth.currentNonce else {
                    onError(String(localized: "인증 요청이 만료되었습니다. 다시 시도해주세요"))
                    return
                }
                Task {
                    do {
                        try await auth.signInWithApple(idToken: idToken, nonce: nonce)
                        await MainActor.run { onSuccess() }
                    } catch {
                        await MainActor.run {
                            onError(AuthService.parseAuthError(error))
                        }
                    }
                }
            case .failure(let error):
                // 사용자가 취소한 경우 에러 표시하지 않음
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                onError(String(localized: "Apple 로그인에 실패했습니다"))
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
