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

            Text(controller.currentVariant?.personaName ?? controller.currentScenario?.personaName ?? "AI")
                .font(.title2.bold())
                .foregroundStyle(.white)

            if let role = controller.currentScenario?.personaRole {
                Text(LocalizedStringKey(role))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            statusBadge
                .padding(.top, 2)

            // 경과 시간 + 남은 시간
            HStack(spacing: 8) {
                Text(elapsedFormatted)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))

                let remaining = max(0, controller.maxDurationSeconds - elapsed)
                if remaining <= 30 && remaining > 0 {
                    Text("(\(remaining)초 남음)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
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

                    // 보이지 않는 bottom anchor — 마지막 bubble 아래 여유 공간을 확보해
                    // scrollTo(anchor: .bottom) 호출 시 실제 bubble이 잘리지 않게 함.
                    Color.clear
                        .frame(height: 12)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .onChange(of: voice.transcript.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: voice.partialAssistantText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: voice.partialUserText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: voice.transcript.last?.translation) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // LazyVStack의 레이아웃이 반영된 후 스크롤되도록 한 프레임 지연.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    private func transcriptBubble(_ entry: RealtimeVoiceService.TranscriptEntry) -> some View {
        transcriptBubble(
            speaker: entry.speaker,
            text: entry.text,
            translation: entry.translation,
            isPartial: false
        )
    }

    private func transcriptBubble(
        speaker: RealtimeVoiceService.Speaker,
        text: String,
        translation: String? = nil,
        isPartial: Bool
    ) -> some View {
        HStack(alignment: .top) {
            if speaker == .user { Spacer(minLength: 40) }

            VStack(alignment: speaker == .user ? .trailing : .leading, spacing: 4) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(speaker == .user ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(speaker == .user ? Color.blue : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(isPartial ? 0.7 : 1)

                if let translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(
                            speaker == .user
                                ? Color.white.opacity(0.7)
                                : Color.white.opacity(0.55)
                        )
                        .padding(.horizontal, 6)
                        .multilineTextAlignment(speaker == .user ? .trailing : .leading)
                }
            }

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

            // 스피커 ↔ 수화기 토글
            Button {
                voice.setSpeakerEnabled(!voice.isSpeakerOn)
            } label: {
                controlButton(
                    systemName: voice.isSpeakerOn ? "speaker.wave.3.fill" : "ear.fill",
                    color: voice.isSpeakerOn ? .white : .white.opacity(0.9),
                    background: voice.isSpeakerOn ? Color.white.opacity(0.3) : Color.white.opacity(0.12)
                )
            }
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak timer] _ in
            Task { @MainActor in
                elapsed = controller.elapsedSeconds
                // 최대 시간 도달 시 자동 종료 (1회만 호출되도록 즉시 타이머 정지)
                if elapsed >= controller.maxDurationSeconds {
                    timer?.invalidate()
                    controller.endCurrentCall()
                }
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
