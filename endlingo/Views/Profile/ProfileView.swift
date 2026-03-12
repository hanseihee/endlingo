import SwiftUI

struct ProfileView: View {
    @AppStorage("selectedLevel") private var selectedLevel: String = ""
    @AppStorage("selectedEnvironment") private var selectedEnvironment: String = ""
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    private var level: EnglishLevel? {
        EnglishLevel(rawValue: selectedLevel)
    }

    private var environment: LearningEnvironment? {
        LearningEnvironment(rawValue: selectedEnvironment)
    }

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

                    HStack {
                        Text("알림 시간")
                        Spacer()
                        Text(String(format: "%d:%02d", notificationHour, notificationMinute))
                            .foregroundStyle(.secondary)
                    }
                }

                // 계정
                Section("계정") {
                    Label("로그인", systemImage: "person.badge.key")
                        .foregroundStyle(.blue)
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

                // 초기화
                Section {
                    Button(role: .destructive) {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("온보딩 다시 하기", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("프로필")
        }
    }
}
