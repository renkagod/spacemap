import Foundation

/// Russian number formatting, independent of the system locale.
public enum Format {
    private static let units = ["Б", "КБ", "МБ", "ГБ", "ТБ", "ПБ"]

    /// Decimal units, like Finder: 1 ГБ = 1000³ bytes.
    public static func bytes(_ value: Int64) -> String {
        var amount = Double(max(0, value))
        var unit = 0
        while amount >= 999.5 && unit < units.count - 1 {
            amount /= 1000
            unit += 1
        }
        if unit == 0 { return "\(Int(amount)) Б" }
        let text: String
        if amount >= 99.95 {
            text = String(format: "%.0f", amount)
        } else if amount >= 9.995 {
            text = String(format: "%.1f", amount)
        } else {
            text = String(format: "%.2f", amount)
        }
        return text.replacingOccurrences(of: ".", with: ",") + " " + units[unit]
    }

    /// 1234567 → "1 234 567" (narrow no-break spaces).
    public static func count(_ value: Int64) -> String {
        let digits = String(abs(value))
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { result.append("\u{202F}") }
            result.append(character)
        }
        return value < 0 ? "−" + result : result
    }

    public static func plural(_ value: Int64, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(value) % 100
        if (11...14).contains(n) { return many }
        switch n % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    public static func files(_ value: Int64) -> String {
        "\(count(value)) \(plural(value, "файл", "файла", "файлов"))"
    }

    public static func items(_ value: Int64) -> String {
        "\(count(value)) \(plural(value, "объект", "объекта", "объектов"))"
    }

    public static func folders(_ value: Int64) -> String {
        "\(count(value)) \(plural(value, "папка", "папки", "папок"))"
    }

    public static func percent(_ fraction: Double) -> String {
        let value = max(0, fraction) * 100
        let text: String
        if value == 0 {
            text = "0"
        } else if value < 0.1 {
            text = "<0,1"
        } else if value < 10 {
            text = String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        } else {
            text = String(format: "%.0f", value)
        }
        return text + "\u{202F}%"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 10 {
            return String(format: "%.1f", seconds).replacingOccurrences(of: ".", with: ",") + " с"
        }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) с" }
        return "\(total / 60) мин \(String(format: "%02d", total % 60)) с"
    }
}
