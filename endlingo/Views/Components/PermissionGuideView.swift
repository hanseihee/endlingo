import SwiftUI

/// 권한 거부 시 설정 앱 이동 안내 뷰
struct PermissionGuideView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear.badge")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("마이크와 음성 인식 권한이 필요합니다")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)

            Text("설정에서 권한을 허용해주세요")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("설정으로 이동", systemImage: "arrow.up.forward.app")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
    }
}
