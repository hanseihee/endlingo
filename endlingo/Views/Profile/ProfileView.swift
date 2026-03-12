import SwiftUI

struct ProfileView: View {
    @AppStorage("selectedLevel") private var selectedLevel: String = ""
    @AppStorage("selectedEnvironment") private var selectedEnvironment: String = ""
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0

    @State private var auth = AuthService.shared
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var notificationTime = Date()

    var body: some View {
        NavigationStack {
            List {
                // 학습 설정
                Section("학습 설정") {
                    Picker("레벨", selection: $selectedLevel) {
                        ForEach(EnglishLevel.allCases) { lvl in
                            Text("\(lvl.emoji) \(lvl.title)")
                                .tag(lvl.rawValue)
                        }
                    }

                    Picker("환경", selection: $selectedEnvironment) {
                        ForEach(LearningEnvironment.allCases) { env in
                            Text("\(env.emoji) \(env.title)")
                                .tag(env.rawValue)
                        }
                    }

                    DatePicker("알림 시간", selection: $notificationTime, displayedComponents: .hourAndMinute)
                        .onChange(of: notificationTime) { _, newValue in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            notificationHour = comps.hour ?? 9
                            notificationMinute = comps.minute ?? 0
                            NotificationService.shared.scheduleDailyNotification(
                                hour: notificationHour, minute: notificationMinute
                            )
                        }
                }

                // 계정
                Section("계정") {
                    if auth.isLoggedIn {
                        HStack {
                            Label("이메일", systemImage: "person.circle.fill")
                            Spacer()
                            Text(auth.userEmail ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("회원탈퇴", systemImage: "person.crop.circle.badge.minus")
                        }
                    } else {
                        NavigationLink {
                            ProfileLoginView()
                        } label: {
                            Label("이메일로 로그인", systemImage: "envelope.fill")
                                .foregroundStyle(.blue)
                        }

                        Text("게스트 모드")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 앱 정보
                Section("앱 정보") {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .navigationTitle("프로필")
            .onAppear {
                var comps = DateComponents()
                comps.hour = notificationHour
                comps.minute = notificationMinute
                notificationTime = Calendar.current.date(from: comps) ?? Date()
            }
            .alert("로그아웃", isPresented: $showLogoutConfirm) {
                Button("로그아웃", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("로그아웃하시겠습니까?")
            }
            .alert("회원탈퇴", isPresented: $showDeleteConfirm) {
                Button("탈퇴하기", role: .destructive) {
                    Task { await auth.deleteAccount() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("계정을 삭제하면 복구할 수 없습니다. 정말 탈퇴하시겠습니까?")
            }
        }
    }
}

// MARK: - 프로필에서 로그인 (게스트 → 회원 전환)

private struct ProfileLoginView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showResetPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    @State private var auth = AuthService.shared

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    var body: some View {
        Form {
            Section {
                TextField("이메일", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("비밀번호 (6자 이상)", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(isSignUp ? "회원가입" : "로그인")
                                .font(.body.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(!isFormValid || isLoading)
            }

            Section {
                Button {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = nil
                    }
                } label: {
                    Text(isSignUp ? "이미 계정이 있으신가요? 로그인" : "계정이 없으신가요? 회원가입")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                }

                if !isSignUp {
                    Button {
                        resetEmail = email
                        resetSent = false
                        showResetPassword = true
                    } label: {
                        Text("비밀번호 찾기")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(isSignUp ? "회원가입" : "로그인")
        .navigationBarTitleDisplayMode(.inline)
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
                            dismiss()
                        } else {
                            errorMessage = "확인 메일을 발송했습니다. 이메일의 링크를 클릭한 후 로그인해주세요."
                            isSignUp = false
                            isLoading = false
                        }
                    }
                } else {
                    try await auth.signIn(email: trimmedEmail, password: password)
                    await MainActor.run { dismiss() }
                }
            } catch {
                await MainActor.run {
                    errorMessage = parseError(error)
                    isLoading = false
                }
            }
        }
    }

    private func parseError(_ error: Error) -> String {
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
}
