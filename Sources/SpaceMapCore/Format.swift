import Foundation

/// Numbers and sizes in the current UI language (`Localization.current`).
public enum Format {
    private static let unitKeys = ["unit.B", "unit.KB", "unit.MB", "unit.GB", "unit.TB", "unit.PB"]

    /// Decimal units, like Finder: 1 GB = 1000³ bytes.
    public static func bytes(_ value: Int64) -> String {
        let translation = Localization.current
        var amount = Double(max(0, value))
        var unit = 0
        while amount >= 999.5 && unit < unitKeys.count - 1 {
            amount /= 1000
            unit += 1
        }
        let name = translation.string(unitKeys[unit])
        if unit == 0 { return "\(translation.integer(Int64(amount))) \(name)" }
        let digits = amount >= 99.95 ? 0 : amount >= 9.995 ? 1 : 2
        return "\(translation.decimal(amount, digits: digits)) \(name)"
    }

    /// 1234567 → "1,234,567" in English, "1 234 567" in Russian.
    public static func count(_ value: Int64) -> String {
        Localization.current.integer(value)
    }

    public static func files(_ value: Int64) -> String {
        Localization.current.plural("count.files", value)
    }

    public static func items(_ value: Int64) -> String {
        Localization.current.plural("count.items", value)
    }

    public static func folders(_ value: Int64) -> String {
        Localization.current.plural("count.folders", value)
    }

    public static func percent(_ fraction: Double) -> String {
        let translation = Localization.current
        let value = max(0, fraction) * 100
        let text: String
        if value == 0 {
            text = translation.integer(0)
        } else if value < 0.1 {
            text = "<" + translation.decimal(0.1, digits: 1)
        } else if value < 10 {
            text = translation.decimal(value, digits: 1)
        } else {
            text = translation.decimal(value, digits: 0)
        }
        return translation.format("format.percent", [text])
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let translation = Localization.current
        if seconds < 10 {
            return translation.format("duration.seconds", [translation.decimal(seconds, digits: 1)])
        }
        let total = Int(seconds.rounded())
        if total < 60 { return translation.format("duration.seconds", [String(total)]) }
        return translation.format("duration.minutes", [String(total / 60), String(format: "%02d", total % 60)])
    }
}
