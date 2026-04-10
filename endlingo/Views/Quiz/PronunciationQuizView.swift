import SwiftUI

struct PronunciationQuizView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PronunciationQuizViewModel()
    @State private var recognition = SpeechRecognitionService.shared
    @State private var speech = SpeechService.shared
    @State private var selectedSource: QuizWordSource = .builtin
    @State private var autoStartTask: Task<Void, Never>?
    @State private var countdown: Int = 0
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isFinished {
                    quizSummary
                } else if viewModel.questions.isEmpty {
                    quizSetup
                } else {
                    quizQuestion
                }
            }
            .navigationTitle("발음 퀴즈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        cancelAutoStart()
                        cancelCountdown()
                        recognition.reset()
                        speech.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                cancelAutoStart()
                cancelCountdown()
                recognition.reset()
                speech.stop()
            }
            // TTS 완료 후 자동 녹음 재개
            .onChange(of: speech.speakingId) { old, new in
                if old != nil && new == nil
                    && viewModel.currentScore == nil
                    && !viewModel.isFinished
                    && !viewModel.questions.isEmpty {
                    autoStartRecording()
                }
            }
        }
    }

    // MARK: - 설정

    private var quizSetup: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("quiz-pronunciation")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            Text("발음 퀴즈")
                .font(.title2.bold())

            Text("단어를 보고 소리 내어 읽어보세요")
                .font(.callout)
                .foregroundStyle(.secondary)

            // 소스 선택
            VStack(spacing: 12) {
                Text("단어 범위")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("범위", selection: $selectedSource) {
                    ForEach(QuizWordSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }

            if !viewModel.canStart(source: selectedSource) {
                Text("단어를 5개 이상 저장해야\n퀴즈를 시작할 수 있습니다")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if viewModel.canStart(source: selectedSource) {
                Button {
                    viewModel.generate(source: selectedSource)
                    autoStartRecording()
                } label: {
                    Text("시작하기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - 문제

    private var quizQuestion: some View {
        VStack(spacing: 24) {
            // 프로그레스
            HStack {
                Text("\(viewModel.currentIndex + 1) / \(viewModel.questions.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("+\(viewModel.totalXPEarned) XP")
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
            }
            .padding(.horizontal, 24)

            ProgressView(value: viewModel.progress)
                .tint(.teal)
                .padding(.horizontal, 24)

            Spacer()

            if let question = viewModel.currentQuestion {
                // 단어 + 뜻
                VStack(spacing: 8) {
                    Text("이 단어를 읽어보세요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(question.word)
                            .font(.system(size: 36, weight: .bold, design: .rounded))

                        // 듣기 버튼: 녹음 중지 → TTS → 완료 후 자동 녹음 재개
                        Button {
                            speakWord()
                        } label: {
                            Image(systemName: speech.isSpeaking(id: "pq-\(viewModel.currentIndex)")
                                  ? "speaker.wave.3.fill" : "speaker.wave.2")
                                .font(.title3)
                                .foregroundStyle(.teal)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(question.meaning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 상태별 콘텐츠
                if let score = viewModel.currentScore {
                    resultView(score: score)
                } else {
                    micArea
                }
            }

            Spacer(minLength: 16)
        }
    }

    // MARK: - 마이크 영역 (자동 녹음)

    private var micArea: some View {
        VStack(spacing: 16) {
            switch recognition.state {
            case .idle:
                // 자동 시작 대기 (탭으로 수동 시작 가능)
                Button {
                    startListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.teal.opacity(0.08))
                            .frame(width: 88, height: 88)
                        Circle()
                            .fill(Color.teal.opacity(0.3))
                            .frame(width: 64, height: 64)
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Text("준비 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .error(let msg):
                if msg.contains(String(localized: "권한")) {
                    PermissionGuideView()
                } else {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button {
                        autoStartRecording()
                    } label: {
                        Label("다시 시도", systemImage: "arrow.counterclockwise")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.teal)
                    }
                }

            case .recording:
                // 실시간 인식 표시
                Text(recognition.liveTranscription.isEmpty
                     ? String(localized: "듣고 있어요...")
                     : recognition.liveTranscription)
                    .font(.body)
                    .foregroundStyle(recognition.liveTranscription.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 24)

                // 녹음 중 인디케이터 (자동 종료됨)
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                    Image(systemName: "waveform")
                        .font(.title)
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }

            case .processing:
                ProgressView()
                    .scaleEffect(1.2)
                Text("분석 중...")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .completed:
                if let result = recognition.result {
                    Color.clear
                        .onAppear { viewModel.judge(score: result.score, spokenText: result.spokenText) }
                }
            }
        }
        .onChange(of: recognition.state) { _, newState in
            if newState == .completed, let result = recognition.result {
                viewModel.judge(score: result.score, spokenText: result.spokenText)
            }
        }
    }

    // MARK: - 결과

    private func resultView(score: Int) -> some View {
        let passed = viewModel.isCorrect == true
        let isLast = viewModel.currentIndex + 1 >= viewModel.questions.count
        let word = viewModel.currentQuestion?.word ?? ""

        return VStack(spacing: 16) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(passed ? .green : .red)

            Text(passed ? String(localized: "정답!") : String(localized: "다시 도전해보세요"))
                .font(.title3.bold())

            Text("\(score)점")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(passed ? .green : .red)

            // 내 발음 표시
            if let spoken = viewModel.spokenText, !spoken.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(spoken)
                        .font(.callout.italic())
                        .foregroundStyle(passed ? .green : .red)
                    Image(systemName: "quote.closing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 외운 단어 체크
            Button {
                viewModel.toggleMastered(word)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isMastered(word)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.isMastered(word) ? .green : .secondary)
                    Text("외운 단어")
                        .foregroundStyle(viewModel.isMastered(word) ? .primary : .secondary)
                }
                .font(.callout)
            }
            .buttonStyle(.plain)

            if !passed {
                // 틀렸을 때: 다시 도전 (카운트다운 기본 동작)
                Button {
                    cancelCountdown()
                    retryQuestion()
                } label: {
                    HStack(spacing: 6) {
                        Text("다시 도전")
                        if countdown > 0 {
                            Text("\(countdown)")
                                .monospacedDigit()
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                Button {
                    cancelCountdown()
                    goToNextQuestion()
                } label: {
                    Text(isLast ? String(localized: "결과 보기") : String(localized: "다음 단어"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
            } else {
                // 맞았을 때: 다음 단어 (카운트다운 기본 동작)
                Button {
                    cancelCountdown()
                    goToNextQuestion()
                } label: {
                    HStack(spacing: 6) {
                        Text(isLast ? String(localized: "결과 보기") : String(localized: "다음 단어"))
                        if countdown > 0 {
                            Text("\(countdown)")
                                .monospacedDigit()
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            startCountdown()
        }
    }

    // MARK: - 결과 요약

    private var quizSummary: some View {
        VStack(spacing: 24) {
            Spacer()

            let total = viewModel.questions.count
            let correct = viewModel.correctCount
            let accuracy = total > 0 ? Int(Double(correct) / Double(total) * 100) : 0

            Image(systemName: accuracy >= 80 ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accuracy >= 80 ? .yellow : .green)

            Text(accuracy >= 80 ? String(localized: "훌륭합니다!") : String(localized: "수고했습니다!"))
                .font(.title2.bold())

            HStack(spacing: 24) {
                SummaryLabel(label: String(localized: "정답"), value: "\(correct)/\(total)")
                SummaryLabel(label: String(localized: "정답률"), value: "\(accuracy)%")
                SummaryLabel(label: String(localized: "획득 XP"), value: "+\(viewModel.totalXPEarned)")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    viewModel.generate(source: selectedSource)
                    autoStartRecording()
                } label: {
                    Text("다시 도전하기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    dismiss()
                } label: {
                    Text("돌아가기")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    /// 0.5초 후 자동 녹음 시작
    private func autoStartRecording() {
        cancelAutoStart()
        autoStartTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard viewModel.currentScore == nil,
                  !viewModel.isFinished,
                  !viewModel.questions.isEmpty else { return }
            guard recognition.state != .recording,
                  recognition.state != .processing else { return }
            startListening()
        }
    }

    private func cancelAutoStart() {
        autoStartTask?.cancel()
        autoStartTask = nil
    }

    private func startListening() {
        guard let question = viewModel.currentQuestion else { return }
        Task {
            await recognition.startRecording(referenceText: question.word, autoStop: true)
        }
    }

    /// 다음 문제로 이동
    private func goToNextQuestion() {
        recognition.reset()
        viewModel.nextQuestion()
        if !viewModel.isFinished {
            autoStartRecording()
        }
    }

    /// 3초 카운트다운 → 정답: 다음 문제 / 오답: 다시 도전
    private func startCountdown() {
        cancelCountdown()
        countdown = 3
        let passed = viewModel.isCorrect == true
        countdownTask = Task {
            for i in [3, 2, 1] {
                countdown = i
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            if passed {
                goToNextQuestion()
            } else {
                retryQuestion()
            }
        }
    }

    /// 같은 문제 다시 도전
    private func retryQuestion() {
        recognition.reset()
        viewModel.currentScore = nil
        viewModel.isCorrect = nil
        viewModel.spokenText = nil
        autoStartRecording()
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = 0
    }

    /// 듣기: 녹음 중지 → TTS 재생 → TTS 완료 시 onChange에서 자동 녹음 재개
    private func speakWord() {
        guard let question = viewModel.currentQuestion else { return }
        cancelAutoStart()
        // 녹음 중이면 중지
        if recognition.state == .recording || recognition.state == .processing {
            recognition.reset()
        }
        speech.speak(question.word, id: "pq-\(viewModel.currentIndex)")
    }
}

private struct SummaryLabel: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
