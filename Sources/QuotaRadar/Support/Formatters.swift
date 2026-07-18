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
        if value >= 1_000_000_000 {
            return compactDecimal(double / 1_000_000_000, maxFractionDigits: 2) + "B"
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", double / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", double / 1_000)
        }
        return "\(value)"
    }

    private static func compactDecimal(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(100, value)))
    }

    static func countdownPercent(_ value: Double) -> String {
        String(format: "%.1f%%", max(0, min(100, value)))
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

    static func subscriptionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func subscriptionRemainingText(_ date: Date, now: Date = Date()) -> String {
        let calendar = localCalendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        if days > 0 {
            return "剩余 \(days) 天"
        }
        if days == 0 {
            return "今天到期"
        }
        return "已过期 \(abs(days)) 天"
    }
}
