import Foundation

enum NumericKeyExtractor {
    static func flatten(_ object: Any, prefix: String = "") -> [String: Any] {
        var result: [String: Any] = [:]
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let nextKey = prefix.isEmpty ? key : "\(prefix).\(key)"
                result[nextKey] = value
                flatten(value, prefix: nextKey).forEach { result[$0.key] = $0.value }
            }
        } else if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                flatten(value, prefix: "\(prefix).\(index)").forEach { result[$0.key] = $0.value }
            }
        }
        return result
    }
}

extension Dictionary where Key == String, Value == Any {
    func firstValue(keys: [String]) -> Int {
        for key in keys {
            if let value = self[key] {
                if let int = value as? Int { return int }
                if let double = value as? Double { return Int(double) }
                if let string = value as? String, let int = Int(string) { return int }
            }
            if let match = first(where: { $0.key.hasSuffix(".\(key)") })?.value {
                if let int = match as? Int { return int }
                if let double = match as? Double { return Int(double) }
                if let string = match as? String, let int = Int(string) { return int }
            }
        }
        return 0
    }

    func stringValue(keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String {
                return value
            }
            if let match = first(where: { $0.key.hasSuffix(".\(key)") })?.value as? String {
                return match
            }
        }
        return nil
    }
}

enum DateParser {
    static func parse(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            return date
        }
        if let seconds = TimeInterval(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
