import SwiftUI

struct RecentActivityCard: View {
    @State private var gamification = GamificationService.shared

    private var activities: [(date: String, items: [GamificationService.ActivityItem])] {
        let grouped = gamification.recentActivities(days: 7)
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, items: $0.value) }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f.string(from: Date())
    }

    private var yesterdayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return f.string(from: yesterday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("최근 활동")
                .font(.headline)

            if activities.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("최근 7일간 활동이 없습니다")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ForEach(Array(activities.enumerated()), id: \.element.date) { index, group in
                    if index > 0 {
                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(displayDate(group.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(item.color)
                                    .frame(width: 24)

                                Text(item.text)
                                    .font(.callout)

                                Spacer()

                                if item.xp > 0 {
                                    Text("+\(item.xp) XP")
                                        .font(.caption.bold())
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func displayDate(_ dateString: String) -> String {
        if dateString == todayString { return String(localized: "오늘") }
        if dateString == yesterdayString { return String(localized: "어제") }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        guard let date = f.date(from: dateString) else { return dateString }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.locale = Locale.current
        display.timeZone = TimeZone(identifier: "Asia/Seoul")
        return display.string(from: date)
    }
}
