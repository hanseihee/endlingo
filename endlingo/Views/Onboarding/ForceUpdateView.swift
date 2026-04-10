import SwiftUI

/// 강제 업데이트 차단 화면. AppUpdateService.shouldForceUpdate가 true일 때 전면 표시.
/// 닫기 없음 — 사용자는 반드시 앱 스토어로 이동해 업데이트해야 함.
struct ForceUpdateView: View {
    let message: String
    let appStoreURL: URL?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image("MainCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)

                VStack(spacing: 12) {
                    Text("업데이트가 필요합니다")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                if let url = appStoreURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("앱 스토어에서 업데이트")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 40)
            }
        }
    }
}

#Preview {
    ForceUpdateView(
        message: "새로운 버전이 필요합니다.\n앱 스토어에서 최신 버전을 받아주세요.",
        appStoreURL: URL(string: "https://apps.apple.com/app/id6760590621")
    )
}
