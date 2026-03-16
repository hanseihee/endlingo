import SwiftUI

struct LoginView: View {
    let onLoginSuccess: () -> Void
    let onGuestLogin: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = !UserDefaults.standard.bool(forKey: "hasAccount")
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSuccessMessage = false
    @State private var showResetPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    @State private var auth = AuthService.shared

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    var body: some View {
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

            // 이메일/비밀번호 폼
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    TextField("이메일", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("비밀번호 (6자 이상)", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(isSuccessMessage ? .green : .red)
                        .multilineTextAlignment(.center)
                }

                // 로그인/회원가입 버튼
                Button {
                    submit()
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isSignUp ? String(localized: "회원가입") : String(localized: "로그인"))
                                .font(.body.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isFormValid ? Color.blue : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!isFormValid || isLoading)

                // 로그인 ↔ 회원가입 전환 + 비밀번호 찾기
                HStack {
                    Button {
                        withAnimation {
                            isSignUp.toggle()
                            errorMessage = nil
                        }
                    } label: {
                        Text(isSignUp ? String(localized: "이미 계정이 있으신가요? **로그인**") : String(localized: "계정이 없으신가요? **회원가입**"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.blue)
                    }

                    if !isSignUp {
                        Spacer()
                        Button {
                            resetEmail = email
                            resetSent = false
                            showResetPassword = true
                        } label: {
                            Text("비밀번호 찾기")
                                .font(.callout)
                                .foregroundStyle(.blue)
                        }
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
                .disabled(isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
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
    }

    private func submit() {
        guard isFormValid else { return }
        isLoading = true
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                if isSignUp {
                    let confirmed = try await auth.signUp(email: trimmedEmail, password: password)
                    await MainActor.run {
                        if confirmed {
                            onLoginSuccess()
                        } else {
                            isSuccessMessage = true
                            errorMessage = String(localized: "확인 메일을 발송했습니다. 이메일의 링크를 클릭한 후 로그인해주세요.")
                            isSignUp = false
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
