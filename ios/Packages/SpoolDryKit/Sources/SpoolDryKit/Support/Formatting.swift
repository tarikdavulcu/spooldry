import Foundation

public enum TemperatureUnit: String, CaseIterable, Codable, Sendable {
    case celsius
    case fahrenheit

    public func convert(fromCelsius c: Double) -> Double {
        switch self {
        case .celsius: return c
        case .fahrenheit: return c * 9.0 / 5.0 + 32.0
        }
    }

    public func toCelsius(_ v: Double) -> Double {
        switch self {
        case .celsius: return v
        case .fahrenheit: return (v - 32.0) * 5.0 / 9.0
        }
    }

    public var symbol: String { self == .celsius ? "°C" : "°F" }

    /// Default from the user's locale (US -> Fahrenheit).
    public static func preferred(for locale: Locale = .current) -> TemperatureUnit {
        if #available(iOS 16, macOS 13, *) {
            return locale.measurementSystem == .us ? .fahrenheit : .celsius
        }
        return .celsius
    }
}

public enum SpoolDryFormat {
    /// "48.2°C" / "118.8°F", or "--" when there is no valid reading.
    public static func temperature(_ celsius: Double?, unit: TemperatureUnit, fractionDigits: Int = 1,
                                   locale: Locale = .current) -> String {
        guard let c = celsius else { return "--" }
        let nf = NumberFormatter()
        nf.locale = locale
        nf.minimumFractionDigits = fractionDigits
        nf.maximumFractionDigits = fractionDigits
        let v = unit.convert(fromCelsius: c)
        return (nf.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)) + unit.symbol
    }

    /// "18% RH" style value (without the RH suffix; callers add the label).
    public static func humidity(_ percent: Double?, fractionDigits: Int = 0, locale: Locale = .current) -> String {
        guard let p = percent else { return "--" }
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .percent
        nf.minimumFractionDigits = fractionDigits
        nf.maximumFractionDigits = fractionDigits
        return nf.string(from: NSNumber(value: p / 100.0)) ?? "\(Int(p.rounded()))%"
    }

    /// "02:41" (hours:minutes). Used where a compact countdown is needed.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        // Countdown style: round up to whole minutes so "59 s left" reads 00:01, never 00:00.
        guard seconds.isFinite else { return "--:--" }
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }

    /// Localized duration such as "8 h 30 min".
    public static func duration(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let f = DateComponentsFormatter()
        var cal = Calendar.current
        cal.locale = locale
        f.calendar = cal
        f.unitsStyle = .abbreviated
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: max(0, seconds)) ?? hoursMinutes(seconds)
    }
}
