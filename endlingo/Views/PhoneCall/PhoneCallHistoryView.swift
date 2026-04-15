import SwiftUI

/// 저장된 AI 전화영어 통화 기록 리스트. 탭하면 상세(트랜스크립트) 화면으로 이동.
/// 로그인 상태면 서버에서 최신 기록을 당겨옵니다.
struct PhoneCallHistoryView: View {
    private let history = PhoneCallHistoryService.shared
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if history.records.isEmpty {
                emptyState
            } else {
                recordList
            }
        }
        .navigationTitle("통화 기록")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isRefreshing = true
            await history.refreshFromServer()
            isRefreshing = false
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "phone.badge.waveform")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("아직 저장된 통화가 없어요")
                .font(.headline)
            Text("30초 이상 통화하면 자동으로 기록이 남아요")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var recordList: some View {
        List {
            ForEach(history.records) { record in
                NavigationLink {
                    PhoneCallDetailView(record: record)
                } label: {
                    row(record)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    history.remove(id: history.records[index].id)
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ record: PhoneCallRecord) -> some View {
        HStack(spacing: 12) {
            Text(record.personaEmoji)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(record.scenarioTitle))
                        .font(.body.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(record.personaName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(formattedDuration(record.durationSeconds), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Label("\(record.transcript.count)", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(record.startedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Detail

struct PhoneCallDetailView: View {
    let record: PhoneCallRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(record.transcript.enumerated()), id: \.offset) { _, line in
                        bubble(line)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(Text(LocalizedStringKey(record.scenarioTitle)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(record.personaEmoji)
                .font(.system(size: 48))
                .frame(width: 80, height: 80)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(Circle())

            Text(record.personaName)
                .font(.headline)

            HStack(spacing: 18) {
                Label(formattedDuration, systemImage: "clock")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(record.startedAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func bubble(_ line: PhoneCallRecord.TranscriptLine) -> some View {
        HStack(alignment: .top) {
            if line.speaker == "user" { Spacer(minLength: 40) }

            VStack(alignment: line.speaker == "user" ? .trailing : .leading, spacing: 3) {
                Text(line.speaker == "user" ? String(localized: "나") : record.personaName)
                    .font(.caption2.bold())
                    .foregroundStyle(line.speaker == "user" ? .blue : .secondary)

                Text(line.text)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        line.speaker == "user"
                            ? Color.blue.opacity(0.12)
                            : Color(.secondarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .multilineTextAlignment(line.speaker == "user" ? .trailing : .leading)
                }
            }

            if line.speaker == "assistant" { Spacer(minLength: 40) }
        }
    }

    private var formattedDuration: String {
        let m = record.durationSeconds / 60
        let s = record.durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    NavigationStack {
        PhoneCallHistoryView()
    }
}
