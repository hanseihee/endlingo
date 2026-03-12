import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "calendar")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("아직 학습 기록이 없습니다")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("매일 레슨을 확인하면 기록이 쌓여요")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("기록")
        }
    }
}
