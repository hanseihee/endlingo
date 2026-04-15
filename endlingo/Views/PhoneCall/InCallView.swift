import SwiftUI

/// 통화 중 화면 (앱 내). 사용자가 CallKit 수신 UI에서 "앱으로 돌아가기"를 누르면 이 화면이 보입니다.
/// CallKit이 자체 통화 UI를 유지하므로 이 화면은 **보조**입니다 — 트랜스크립트와 힌트를 제공합니다.
struct InCallView: View {
    private let controller = PhoneCallController.shared
    private let voice = RealtimeVoiceService.shared

    @State private var elapsed: Int = 0
    @State private var timer: Timer?
    @State private var isMuted: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(.systemGray6).opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                callerHeader
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                transcriptList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
                    .padding(.bottom, 32)
            }
        }
        .onAppear {
            startTimer()
            // VoiceService의 현재 mute 상태 동기화
            isMuted = voice.isMuted
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Header

    private var callerHeader: some View {
        VStack(spacing: 10) {
            Text(controller.currentScenario?.emoji ?? "📞")
                .font(.system(size: 68))
                .frame(width: 120, height: 120)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            Text(controller.currentScenario?.personaName ?? "AI")
                .font(.title2.bold())
                .foregroundStyle(.white)

            if let role = controller.currentScenario?.personaRole {
                Text(LocalizedStringKey(role))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            statusBadge
                .padding(.top, 2)

            Text(elapsedFormatted)
                .font(.body.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch controller.phase {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).tint(.white)
                Text("연결 중…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())

        case .active:
            HStack(spacing: 6) {
                Circle()
                    .fill(voice.isAssistantSpeaking ? Color.green : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(voice.isAssistantSpeaking ? "상대방이 말하는 중" : "통화 중")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())

        default:
            EmptyView()
        }
    }

    // MARK: - Transcript

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(voice.transcript) { entry in
                        transcriptBubble(entry)
                            .id(entry.id)
                    }

                    // 실시간 partial 표시
                    if !voice.partialUserText.isEmpty {
                        transcriptBubble(speaker: .user, text: voice.partialUserText, isPartial: true)
                            .id("partial-user")
                    }
                    if !voice.partialAssistantText.isEmpty {
                        transcriptBubble(speaker: .assistant, text: voice.partialAssistantText, isPartial: true)
                            .id("partial-assistant")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: voice.transcript.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: voice.partialAssistantText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if !voice.partialAssistantText.isEmpty {
                proxy.scrollTo("partial-assistant", anchor: .bottom)
            } else if !voice.partialUserText.isEmpty {
                proxy.scrollTo("partial-user", anchor: .bottom)
            } else if let last = voice.transcript.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func transcriptBubble(_ entry: RealtimeVoiceService.TranscriptEntry) -> some View {
        transcriptBubble(speaker: entry.speaker, text: entry.text, isPartial: false)
    }

    private func transcriptBubble(
        speaker: RealtimeVoiceService.Speaker,
        text: String,
        isPartial: Bool
    ) -> some View {
        HStack {
            if speaker == .user { Spacer(minLength: 40) }

            Text(text)
                .font(.callout)
                .foregroundStyle(speaker == .user ? .white : .black)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(speaker == .user ? Color.blue : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .opacity(isPartial ? 0.7 : 1)

            if speaker == .assistant { Spacer(minLength: 40) }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 28) {
            // 음소거
            Button {
                isMuted.toggle()
                controller.setMuted(isMuted)
            } label: {
                controlButton(
                    systemName: isMuted ? "mic.slash.fill" : "mic.fill",
                    color: isMuted ? .white : .white.opacity(0.9),
                    background: isMuted ? Color.white.opacity(0.3) : Color.white.opacity(0.12)
                )
            }

            // 종료
            Button {
                controller.endCurrentCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.red)
                    .clipShape(Circle())
                    .shadow(color: Color.red.opacity(0.4), radius: 10, y: 4)
            }

            // 트랜스크립트 토글 (placeholder — 이미 항상 표시 중)
            controlButton(
                systemName: "captions.bubble.fill",
                color: .white.opacity(0.9),
                background: Color.white.opacity(0.12)
            )
            .opacity(0.4) // 비활성 상태 표시
        }
    }

    private func controlButton(systemName: String, color: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 56, height: 56)
            .background(background)
            .clipShape(Circle())
    }

    // MARK: - Timer

    private var elapsedFormatted: String {
        let m = elapsed / 60
        let s = elapsed % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsed = controller.elapsedSeconds
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    InCallView()
}
