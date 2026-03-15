import SwiftUI

struct PronunciationPracticeView: View {
    let sentence: String
    let scenarioTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var recognition = SpeechRecognitionService.shared
    @State private var gamification = GamificationService.shared
    @State private var xpAwarded = false
    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    // 헤더
                    VStack(spacing: 4) {
                        Text("따라 읽기")
                            .font(.title2.bold())
                        Text(scenarioTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    // 참조 문장
                    VStack(spacing: 8) {
                        Label("이 문장을 읽어보세요", systemImage: "text.quote")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ZStack(alignment: .topTrailing) {
                            Text(sentence)
                                .font(.title3.weight(.medium))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.trailing, 20)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.08))
                                )

                            SpeakButton(text: sentence, id: "practice-sentence")
                        }
                    }
                    .padding(.horizontal, 20)

                    // 상태별 콘텐츠
                    stateContent
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onDisappear {
            recognition.reset()
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        switch recognition.state {
        case .idle:
            idleContent
        case .recording:
            recordingContent
        case .processing:
            processingContent
        case .completed:
            if let result = recognition.result {
                resultContent(result)
            }
        case .error(let message):
            errorContent(message)
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Text("아래 버튼을 누르고\n문장을 소리 내어 읽어보세요")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            micButton
                .padding(.top, 8)
        }
    }

    // MARK: - Recording

    private var recordingContent: some View {
        VStack(spacing: 20) {
            // 실시간 인식 텍스트
            VStack(spacing: 8) {
                Label("인식된 텍스트", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recognition.liveTranscription.isEmpty
                     ? "듣고 있어요..."
                     : recognition.liveTranscription)
                    .font(.body)
                    .foregroundStyle(recognition.liveTranscription.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 60)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
            }

            // 녹음 표시
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulseAnimation ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                               value: pulseAnimation)
                Text("녹음 중")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
            .onAppear { pulseAnimation = true }
            .onDisappear { pulseAnimation = false }

            // 정지 버튼
            Button {
                recognition.stopRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.15))
                        .frame(width: 80, height: 80)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                }
            }
        }
    }

    // MARK: - Processing

    private var processingContent: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            ProgressView()
                .scaleEffect(1.2)
            Text("분석 중...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result

    private func resultContent(_ result: PronunciationResult) -> some View {
        VStack(spacing: 24) {
            // 점수
            VStack(spacing: 8) {
                Text(result.grade.emoji)
                    .font(.system(size: 48))

                Text(result.grade.message)
                    .font(.title3.bold())

                Text("\(result.score)점")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(result.grade.color)
            }

            // 내가 읽은 문장
            VStack(alignment: .leading, spacing: 6) {
                Label("내가 읽은 문장", systemImage: "mic.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 0) {
                    spokenWordsColored(result.spokenWordResults)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        if recognition.isPlayingRecording {
                            recognition.stopPlayback()
                        } else {
                            recognition.playRecording()
                        }
                    } label: {
                        Image(systemName: recognition.isPlayingRecording
                              ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
            }

            // 단어별 결과
            VStack(alignment: .leading, spacing: 8) {
                Label("단어별 결과", systemImage: "text.word.spacing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                wordResultsFlow(result.wordResults)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )

                // 범례
                HStack(spacing: 16) {
                    legendItem(color: .green, text: "정확")
                    legendItem(color: .orange, text: "유사")
                    legendItem(color: .red, text: "틀림")
                }
                .font(.caption2)
                .frame(maxWidth: .infinity)
            }

            // XP 보상
            if !xpAwarded && result.score >= 50 {
                let xp = result.score >= 90 ? 15 : result.score >= 70 ? 10 : 5
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("+\(xp) XP")
                        .font(.callout.bold())
                        .foregroundStyle(.blue)
                }
                .onAppear {
                    awardXP(result.score)
                }
            }

            // 액션 버튼
            HStack(spacing: 12) {
                Button {
                    recognition.reset()
                } label: {
                    Label("다시 도전", systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                        )
                }

                Button {
                    dismiss()
                } label: {
                    Text("완료")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                }
            }
        }
    }

    // MARK: - Error

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            micButton
        }
    }

    // MARK: - Components

    private var micButton: some View {
        Button {
            Task {
                await recognition.startRecording(referenceText: sentence)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 64, height: 64)
                Image(systemName: "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
    }

    private func wordResultsFlow(_ words: [PronunciationResult.WordResult]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(words) { word in
                Text(word.word)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(word.status.color.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(word.status.color.opacity(0.4), lineWidth: 1)
                    )
                    .foregroundStyle(word.status.color)
            }
        }
    }

    private func spokenWordsColored(_ words: [PronunciationResult.WordResult]) -> some View {
        var attributed = AttributedString()
        for (index, word) in words.enumerated() {
            var part = AttributedString(word.word)
            switch word.status {
            case .correct:
                part.foregroundColor = .primary
                part.font = .callout
            case .close:
                part.foregroundColor = .orange
                part.font = .callout
            case .wrong:
                // 매칭 안 된 spoken 단어 = 불필요한 추가 단어 → 회색 + 취소선
                part.foregroundColor = .secondary
                part.font = .callout
                part.strikethroughStyle = .single
            }
            attributed.append(part)
            if index < words.count - 1 {
                attributed.append(AttributedString(" "))
            }
        }
        return Text(attributed)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func awardXP(_ score: Int) {
        guard !xpAwarded else { return }
        xpAwarded = true
        gamification.awardPronunciationXP(score: score)
        AnalyticsService.logPronunciationPractice(score: score)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX

            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }

            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubview]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }

        return rows
    }
}
