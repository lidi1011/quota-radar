import Foundation

enum RadarFormatters {
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        return calendar
    }

    static func compactTokens(_ value: Int) -> String {
        let double = Double(value)
        if value >= 1_000_000 {
            return String(format: "%.1fM", double / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", double / 1_000)
        }
        return "\(value)"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(100, value)))
    }

    static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func resetDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
