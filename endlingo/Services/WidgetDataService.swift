import Foundation
import WidgetKit

/// 메인 앱 ↔ 위젯 간 데이터 공유
enum WidgetDataService {
    private static let suiteName = "group.com.realmasse.yeongeohaja"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// 메인 앱에서 호출: 오늘의 문장을 위젯용으로 저장
    static func saveForWidget(sentenceEn: String, sentenceKo: String, level: String, environment: String, date: String) {
        guard let defaults = shared else {
            print("[Widget] App Group UserDefaults 생성 실패")
            return
        }
        defaults.set(sentenceEn, forKey: "widget_sentenceEn")
        defaults.set(sentenceKo, forKey: "widget_sentenceKo")
        defaults.set(level, forKey: "widget_level")
        defaults.set(environment, forKey: "widget_environment")
        defaults.set(date, forKey: "widget_date")
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        print("[Widget] 데이터 저장 완료: \(sentenceEn.prefix(30))...")
    }

    /// 위젯에서 호출: 저장된 데이터 읽기
    static func load() -> WidgetLessonData {
        guard let defaults = shared else { return .placeholder }
        return WidgetLessonData(
            sentenceEn: defaults.string(forKey: "widget_sentenceEn") ?? "",
            sentenceKo: defaults.string(forKey: "widget_sentenceKo") ?? "",
            level: defaults.string(forKey: "widget_level") ?? "",
            environment: defaults.string(forKey: "widget_environment") ?? "",
            date: defaults.string(forKey: "widget_date") ?? ""
        )
    }
}

struct WidgetLessonData {
    let sentenceEn: String
    let sentenceKo: String
    let level: String
    let environment: String
    let date: String

    var isEmpty: Bool { sentenceEn.isEmpty }

    static let placeholder = WidgetLessonData(
        sentenceEn: "Start learning English today!",
        sentenceKo: "",
        level: "A1",
        environment: "daily",
        date: ""
    )
}
