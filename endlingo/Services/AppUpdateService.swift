import Foundation
import SwiftUI

// MARK: - Model

struct AppConfig: Codable {
    let platform: String
    let minSupportedVersion: String
    let latestVersion: String
    let updateMessageKo: String
    let updateMessageJa: String
    let appStoreURL: String

    enum CodingKeys: String, CodingKey {
        case platform
        case minSupportedVersion = "min_supported_version"
        case latestVersion = "latest_version"
        case updateMessageKo = "update_message_ko"
        case updateMessageJa = "update_message_ja"
        case appStoreURL = "app_store_url"
    }
}

// MARK: - Service

@Observable
@MainActor
final class AppUpdateService {
    static let shared = AppUpdateService()

    /// 강제 업데이트가 필요하면 true. 라우팅이 이 값을 관찰해 차단 화면을 띄움.
    var shouldForceUpdate = false

    /// 현재 로케일에 맞춘 업데이트 메시지.
    var updateMessage = ""

    /// 앱 스토어 링크.
    var appStoreURL: URL?

    private init() {}

    /// 현재 빌드의 MARKETING_VERSION (예: "1.3.0")
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 앱 시작 시 호출. 실패(네트워크 오류 등) 시에는 차단하지 않음 — 오프라인 사용 보장.
    func checkForUpdate() async {
        let configs: [AppConfig] = await SupabaseAPI.fetch(
            "app_config",
            query: "select=*&platform=eq.ios&limit=1"
        )

        guard let config = configs.first else { return }

        if Self.compareVersions(currentVersion, config.minSupportedVersion) < 0 {
            let isJapanese = Locale.current.language.languageCode?.identifier == "ja"
            updateMessage = isJapanese ? config.updateMessageJa : config.updateMessageKo
            appStoreURL = URL(string: config.appStoreURL)
            shouldForceUpdate = true
        }
    }

    /// 시맨틱 버전 비교 (예: "1.3.0" vs "1.2.9"). a < b 면 음수.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(aParts.count, bParts.count)
        for i in 0..<maxCount {
            let ai = i < aParts.count ? aParts[i] : 0
            let bi = i < bParts.count ? bParts[i] : 0
            if ai != bi { return ai - bi }
        }
        return 0
    }
}
