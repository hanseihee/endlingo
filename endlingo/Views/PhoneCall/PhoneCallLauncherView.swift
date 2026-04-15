import SwiftUI

/// AI 전화영어 진입점. 시나리오를 고른 뒤 탭하면 CallKit 수신 UI가 뜹니다.
/// `PhoneCallController.phase`를 관찰해 통화 중(`active`)에는 `InCallView`,
/// 종료 직후(`ended`)에는 `CallEndedView`로 자동 전환합니다.
struct PhoneCallLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedLevel") private var selectedLevelRaw: String = EnglishLevel.a2.rawValue

    private let controller = PhoneCallController.shared

    private var level: EnglishLevel {
        EnglishLevel(rawValue: selectedLevelRaw) ?? .a2
    }

    var body: some View {
        NavigationStack {
            Group {
                switch controller.phase {
                case .idle, .ringing:
                    scenarioList
                case .connecting, .active:
                    InCallView()
                case .ended:
                    CallEndedView(onDismiss: {
                        dismiss()
                    })
                }
            }
            .navigationTitle("AI 전화영어")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .idle = controller.phase {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isInCall)
    }

    private var isInCall: Bool {
        switch controller.phase {
        case .idle: return false
        case .ended: return false
        default: return true
        }
    }

    // MARK: - Scenario List

    private var scenarioList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introCard

                VStack(alignment: .leading, spacing: 8) {
                    Text("시나리오를 선택하세요")
                        .font(.headline)
                        .padding(.horizontal, 16)

                    LazyVStack(spacing: 10) {
                        ForEach(PhoneCallScenario.allCases) { scenario in
                            scenarioRow(scenario)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                availabilityNotice
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "phone.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                Text("베타")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
            }
            Text("실제 전화처럼 AI와 영어로 통화해보세요")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("시나리오를 선택하면 AI가 먼저 전화를 걸어옵니다")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 6) {
                Text("현재 레벨")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text(level.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func scenarioRow(_ scenario: PhoneCallScenario) -> some View {
        Button {
            controller.incomingCall(scenario: scenario, level: level)
        } label: {
            HStack(spacing: 12) {
                Text(scenario.emoji)
                    .font(.system(size: 36))
                    .frame(width: 56, height: 56)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(scenario.title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(LocalizedStringKey(scenario.description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(scenario.personaName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey(scenario.personaRole))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "phone.fill")
                    .foregroundStyle(.white)
                    .font(.callout.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.green)
                    .clipShape(Circle())
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var availabilityNotice: some View {
        if !controller.isCallKitAvailable {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("사용 불가 지역")
                        .font(.footnote.bold())
                }
                .foregroundStyle(.orange)
                Text("현재 지역에서는 전화 기능을 사용할 수 없습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("이용 안내", systemImage: "info.circle")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Text("통화는 OpenAI Realtime API로 연결됩니다. 조용한 환경에서 이어폰 사용을 권장합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    PhoneCallLauncherView()
}
