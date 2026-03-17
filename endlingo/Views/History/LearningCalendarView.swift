import SwiftUI

struct LearningCalendarView: View {
    @State private var gamification = GamificationService.shared
    @State private var displayMonth: Date = Date()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = [
        String(localized: "일"), String(localized: "월"), String(localized: "화"),
        String(localized: "수"), String(localized: "목"), String(localized: "금"), String(localized: "토")
    ]

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }

    private var year: Int { calendar.component(.year, from: displayMonth) }
    private var month: Int { calendar.component(.month, from: displayMonth) }

    private var xpMap: [String: Int] {
        gamification.xpByDate(year: year, month: month)
    }

    private var days: [DayItem] {
        let range = calendar.range(of: .day, in: .month, for: displayMonth)!
        let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")

        var items: [DayItem] = []

        // 빈 셀
        for _ in 0..<firstWeekday {
            items.append(DayItem(day: 0, dateString: "", xp: 0))
        }

        // 날짜 셀
        for day in range {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            let dateStr = formatter.string(from: date)
            let xp = xpMap[dateStr] ?? 0
            items.append(DayItem(day: day, dateString: dateStr, xp: xp))
        }

        return items
    }

    var body: some View {
        VStack(spacing: 16) {
            // 월 네비게이션
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                Spacer()

                Text("\(year)년 \(month)월")
                    .font(.title3.bold())

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled(isCurrentMonth)
            }

            // 요일 헤더
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // 날짜 그리드
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                    if item.day == 0 {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        DayCellView(
                            day: item.day,
                            xp: item.xp,
                            isToday: item.dateString == SupabaseConfig.todayDateString
                        )
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

    private var isCurrentMonth: Bool {
        let now = Date()
        return calendar.component(.year, from: now) == year
            && calendar.component(.month, from: now) == month
    }

    private func moveMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: displayMonth) {
            displayMonth = newDate
        }
    }
}

private struct DayItem {
    let day: Int
    let dateString: String
    let xp: Int
}

private struct DayCellView: View {
    let day: Int
    let xp: Int
    let isToday: Bool

    var body: some View {
        Text("\(day)")
            .font(.subheadline.weight(isToday ? .bold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(cellColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
            )
    }

    private var foregroundColor: Color {
        if isToday && xp == 0 {
            return .teal
        }
        return xp > 0 ? .white : .primary
    }

    private var cellColor: Color {
        if isToday && xp == 0 {
            return Color.accentColor.opacity(0.1)
        }
        switch xp {
        case 0: return Color(.systemGray6)
        case 1...9: return Color.green.opacity(0.35)
        case 10...19: return Color.green.opacity(0.55)
        case 20...29: return Color.green.opacity(0.75)
        default: return Color.green.opacity(0.9)
        }
    }
}
