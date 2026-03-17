import WidgetKit
import SwiftUI

// MARK: - Data

struct WidgetLessonData {
    let sentenceEn: String
    let sentenceKo: String
    let level: String
    let environment: String

    var isEmpty: Bool { sentenceEn.isEmpty }

    static let placeholder = WidgetLessonData(
        sentenceEn: "Open the app to start learning!",
        sentenceKo: "",
        level: "",
        environment: ""
    )

    static func load() -> WidgetLessonData {
        guard let defaults = UserDefaults(suiteName: "group.com.realmasse.yeongeohaja") else {
            return .placeholder
        }
        let en = defaults.string(forKey: "widget_sentenceEn") ?? ""
        if en.isEmpty { return .placeholder }
        return WidgetLessonData(
            sentenceEn: en,
            sentenceKo: defaults.string(forKey: "widget_sentenceKo") ?? "",
            level: defaults.string(forKey: "widget_level") ?? "",
            environment: defaults.string(forKey: "widget_environment") ?? ""
        )
    }
}

// MARK: - Timeline

struct LessonEntry: TimelineEntry {
    let date: Date
    let lesson: WidgetLessonData
}

struct LessonTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LessonEntry {
        LessonEntry(date: .now, lesson: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (LessonEntry) -> Void) {
        completion(LessonEntry(date: .now, lesson: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LessonEntry>) -> Void) {
        let entry = LessonEntry(date: .now, lesson: .load())
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var components = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: 1, to: .now)!)
        components.hour = 7
        let nextUpdate = calendar.date(from: components) ?? calendar.date(byAdding: .hour, value: 12, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Views

struct WidgetContentView: View {
    let entry: LessonEntry
    @Environment(\.widgetFamily) var family

    private static var appName: String {
        let lang = Locale.current.language.languageCode?.identifier ?? "ko"
        return lang == "ja" ? "英語しよ" : "영어하자"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 상단: 로고 + 앱 이름
            HStack(spacing: 6) {
                Image("WidgetLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(Self.appName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !entry.lesson.level.isEmpty {
                    Text(entry.lesson.level)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.teal)
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 8)

            // 영어 문장
            Text(entry.lesson.sentenceEn)
                .font(family == .systemSmall ? .callout.weight(.medium) : .body.weight(.medium))
                .lineLimit(family == .systemSmall ? 4 : 2)
                .minimumScaleFactor(0.8)

            // 한국어 번역 (미디엄에서만)
            if family == .systemMedium, !entry.lesson.sentenceKo.isEmpty {
                Text(entry.lesson.sentenceKo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct YeongeohajaWidget: Widget {
    let kind = "YeongeohajaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LessonTimelineProvider()) { entry in
            WidgetContentView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
                .widgetURL(URL(string: "yeongeohaja://lesson"))
        }
        .configurationDisplayName({
            let lang = Locale.current.language.languageCode?.identifier ?? "ko"
            return lang == "ja" ? "英語しよ" : "영어하자"
        }())
        .description({
            let lang = Locale.current.language.languageCode?.identifier ?? "ko"
            return lang == "ja" ? "毎日新しい英文をチェックしましょう" : "매일 새로운 영어 문장을 확인하세요"
        }())
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
