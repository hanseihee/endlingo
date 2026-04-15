import SwiftUI
import AuthenticationServices

struct ProfileView: View {
    @AppStorage("selectedLevel") private var selectedLevel: String = ""
    @AppStorage("selectedEnvironment") private var selectedEnvironment: String = ""
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("pronunciationAccent") private var pronunciationAccent: String = "en-US"

    @State private var auth = AuthService.shared
    @State private var gamification = GamificationService.shared
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showChangePassword = false
    @State private var notificationTime = Date()
    @State private var showPhoneCall = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // 배지
                Section {
                    NavigationLink {
                        BadgesView()
                    } label: {
                        HStack(spacing: 12) {
                            Image("doodle-trophy")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("배지")
                                    .font(.callout.weight(.semibold))

                                let earned = gamification.earnedBadges.count
                                let total = BadgeType.allCases.count
                                Text("\(earned)/\(total)개 획득")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // AI 전화영어 (베타)
                Section {
                    Button {
                        showPhoneCall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("AI 전화영어")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("베타")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                                Text("AI와 실제 전화처럼 영어로 대화해요")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PhoneCallHistoryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text("통화 기록")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }

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

                    Picker("발음", selection: $pronunciationAccent) {
                        Text("🇺🇸 미국식").tag("en-US")
                        Text("🇬🇧 영국식").tag("en-GB")
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

                        NavigationLink {
                            ChangePasswordView()
                        } label: {
                            Label("비밀번호 변경", systemImage: "lock.rotation")
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
                                .foregroundStyle(Color.accentColor)
                        }

                        Text("게스트 모드")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 앱 공유 & 리뷰
                Section {
                    ShareLink(
                        item: URL(string: "https://apps.apple.com/app/id6760590621")!,
                        subject: Text("영어하자 - 매일 영어 문장 학습"),
                        message: Text("매일 새로운 영어 문장으로 공부하는 앱이야! 같이 해보자 🦉")
                    ) {
                        Label("친구에게 앱 공유하기", systemImage: "square.and.arrow.up")
                    }

                    Link(destination: URL(string: "https://apps.apple.com/app/id6760590621?action=write-review")!) {
                        Label("앱 리뷰 남기기", systemImage: "star.bubble")
                    }
                }

                // 앱 정보
                Section("앱 정보") {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://icons8.com")!) {
                        Text("Icons by Icons8")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

            }
            .safeAreaInset(edge: .bottom) {
                BannerAdView()
                    .padding(.bottom, 4)
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
            .sheet(isPresented: $showPhoneCall) {
                PhoneCallLauncherView()
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
    @State private var isSuccessMessage = false
    @State private var showResetPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false
    @State private var socialLoginError: String?

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
                        .foregroundStyle(isSuccessMessage ? .green : .red)
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
                            Text(isSignUp ? String(localized: "회원가입") : String(localized: "로그인"))
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
                    Text(isSignUp ? String(localized: "이미 계정이 있으신가요? 로그인") : String(localized: "계정이 없으신가요? 회원가입"))
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

            Section {
                AppleSignInButton(onSuccess: { dismiss() }, onError: { socialLoginError = $0 })
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                GoogleSignInButton(onSuccess: { dismiss() }, onError: { socialLoginError = $0 })
                    .frame(height: 44)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if let socialLoginError {
                    Text(socialLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("간편 로그인")
            }
        }
        .navigationTitle(isSignUp ? String(localized: "회원가입") : String(localized: "로그인"))
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
                    let result = try await auth.signUp(email: trimmedEmail, password: password)
                    await MainActor.run {
                        switch result {
                        case .loggedIn:
                            dismiss()
                        case .confirmEmail:
                            isSuccessMessage = true
                            errorMessage = String(localized: "확인 메일을 발송했습니다. 이메일의 링크를 클릭한 후 로그인해주세요.")
                            isSignUp = false
                            isLoading = false
                        case .alreadyExists:
                            isSuccessMessage = false
                            errorMessage = String(localized: "이미 등록된 이메일입니다. 로그인해주세요")
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
                    isSuccessMessage = false
                    errorMessage = AuthService.parseAuthError(error)
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - 비밀번호 변경

private struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSuccess = false

    @State private var auth = AuthService.shared

    private var isFormValid: Bool {
        currentPassword.count >= 6
        && newPassword.count >= 6
        && newPassword == confirmPassword
    }

    private var mismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    var body: some View {
        Form {
            Section {
                SecureField("현재 비밀번호", text: $currentPassword)
                    .textContentType(.password)
            }

            Section {
                SecureField("새 비밀번호 (6자 이상)", text: $newPassword)
                    .textContentType(.newPassword)

                SecureField("새 비밀번호 확인", text: $confirmPassword)
                    .textContentType(.newPassword)

                if mismatch {
                    Text("새 비밀번호가 일치하지 않습니다")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                    changePassword()
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("비밀번호 변경")
                                .font(.body.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(!isFormValid || isLoading)
            }
        }
        .navigationTitle("비밀번호 변경")
        .navigationBarTitleDisplayMode(.inline)
        .alert("비밀번호 변경 완료", isPresented: $isSuccess) {
            Button("확인") { dismiss() }
        } message: {
            Text("비밀번호가 성공적으로 변경되었습니다")
        }
    }

    private func changePassword() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await auth.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
                await MainActor.run {
                    isLoading = false
                    isSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    let msg = "\(error)".lowercased()
                    if msg.contains("invalid login") || msg.contains("invalid_credentials") {
                        errorMessage = String(localized: "현재 비밀번호가 올바르지 않습니다")
                    } else {
                        errorMessage = AuthService.parseAuthError(error)
                    }
                }
            }
        }
    }
}
