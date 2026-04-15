import SwiftUI

/// 통화 종료 후 요약 화면. 통화 시간과 주고받은 대화 내역을 보여주고,
/// 한 번만 XP를 적립합니다.
struct CallEndedView: View {
    let onDismiss: () -> Void

    private let controller = PhoneCallController.shared
    private let voice = RealtimeVoiceService.shared

    @AppStorage("selectedLevel") private var selectedLevelRaw: String = EnglishLevel.a2.rawValue

    @State private var didAwardXP = false
    @State private var didSaveRecord = false
    @State private var isLoadingReview = false
    @State private var didFetchReview = false
    @State private var reviewIssues: [PhoneCallAIService.CallIssue] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                reviewSection
                transcriptSection
                dismissButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .onAppear {
            awardXPIfNeeded()
            saveRecordIfNeeded()
            fetchReviewIfNeeded()
        }
    }

    // MARK: - Review Section

    @ViewBuilder
    private var reviewSection: some View {
        if shouldShowReview {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.bubble.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("영작 피드백")
                        .font(.headline)
                }

                if isLoadingReview {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("피드백을 분석하는 중…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if reviewIssues.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "hands.sparkles.fill")
                            .foregroundStyle(.yellow)
                        Text("훌륭해요! 특별히 수정할 문장이 없어요")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(spacing: 10) {
                        ForEach(reviewIssues) { issue in
                            issueCard(issue)
                        }
                    }
                }
            }
        }
    }

    private func issueCard(_ issue: PhoneCallAIService.CallIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledLine(
                label: "원문",
                text: issue.original,
                color: .red.opacity(0.8)
            )
            labeledLine(
                label: "자연스러운 표현",
                text: issue.improved,
                color: .green
            )
            Text(issue.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func labeledLine(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label))
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    private var shouldShowReview: Bool {
        // 짧은 통화는 피드백 의미 없음
        controller.elapsedSeconds >= 30 && userTurnCount >= 2
    }

    private var userTurnCount: Int {
        voice.transcript.filter { $0.speaker == .user }.count
    }

    private func fetchReviewIfNeeded() {
        guard !didFetchReview, shouldShowReview else { return }
        didFetchReview = true
        isLoadingReview = true

        let lines = voice.transcript.map {
            PhoneCallRecord.TranscriptLine(
                speaker: $0.speaker == .user ? "user" : "assistant",
                text: $0.text,
                translation: $0.translation
            )
        }
        let level = selectedLevelRaw

        Task {
            let issues = await PhoneCallAIService.review(transcript: lines, level: level)
            await MainActor.run {
                reviewIssues = issues
                isLoadingReview = false
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "phone.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("통화가 종료되었습니다")
                .font(.title3.bold())

            if let scenario = controller.currentScenario {
                Text("\(scenario.emoji) \(scenario.personaName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                statRow(label: "통화 시간", value: formattedDuration)
                Divider().frame(height: 24)
                statRow(label: "대화 수", value: "\(voice.transcript.count)")
            }
            .padding(.top, 4)

            if didAwardXP, let xp = earnedXP {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("+\(xp) XP")
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.12))
                .clipShape(Capsule())
            }

            if case .ended(let reason) = controller.phase, let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statRow(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transcript Summary

    @ViewBuilder
    private var transcriptSection: some View {
        if !voice.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("대화 내역")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(voice.transcript) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Text(entry.speaker == .user ? "나" : (controller.currentScenario?.personaName ?? "AI"))
                                .font(.caption.bold())
                                .foregroundStyle(entry.speaker == .user ? .blue : .secondary)
                                .frame(width: 54, alignment: .leading)

                            Text(entry.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("완료")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 8)
    }

    // MARK: - XP

    private var formattedDuration: String {
        let total = controller.elapsedSeconds
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// 1분 미만이면 XP 지급 없음, 1분 이상이면 30 XP 지급 (streak 배수 적용).
    private var earnedXP: Int? {
        guard controller.elapsedSeconds >= 60 else { return nil }
        return GamificationService.XP.phoneCall
    }

    private func awardXPIfNeeded() {
        guard !didAwardXP, controller.elapsedSeconds >= 60 else { return }
        didAwardXP = true
        GamificationService.shared.awardPhoneCallXP()
    }

    /// 통화가 30초 이상이고 대화가 2턴 이상일 때만 기록 저장.
    /// 연결 실패나 즉시 종료된 통화는 기록하지 않습니다.
    private func saveRecordIfNeeded() {
        guard !didSaveRecord,
              controller.elapsedSeconds >= 30,
              voice.transcript.count >= 2,
              let scenario = controller.currentScenario,
              let startedAt = controller.callStartDate else { return }
        didSaveRecord = true

        let lines = voice.transcript.map { entry in
            PhoneCallRecord.TranscriptLine(
                speaker: entry.speaker == .user ? "user" : "assistant",
                text: entry.text,
                translation: entry.translation
            )
        }

        PhoneCallHistoryService.shared.record(
            scenario: scenario,
            durationSeconds: controller.elapsedSeconds,
            transcript: lines,
            startedAt: startedAt
        )
    }
}

#Preview {
    CallEndedView(onDismiss: {})
}
