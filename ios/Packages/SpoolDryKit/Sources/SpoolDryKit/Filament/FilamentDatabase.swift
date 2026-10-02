import Foundation

// Built-in engineering filament knowledge base.
//
// IMPORTANT: Every value here is *typical starting guidance* synthesised from several manufacturers'
// published recommendations. It is not a universal manufacturer requirement. Always follow the data
// sheet of the exact product you print. Manufacturer references (with URLs) are summarised, never copied,
// and were last checked on `FilamentDatabase.lastVerified`.

public enum HumiditySensitivity: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 0, moderate, high, veryHigh

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var localizationKey: String {
        switch self {
        case .low: return "sensitivity.low"
        case .moderate: return "sensitivity.moderate"
        case .high: return "sensitivity.high"
        case .veryHigh: return "sensitivity.veryHigh"
        }
    }
}

public struct ManufacturerReference: Hashable, Codable, Sendable {
    public var manufacturer: String
    public var product: String
    /// Summary of the published value, e.g. "75–85 °C · 8–12 h (blast oven)".
    public var summary: String
    public var url: URL

    public init(_ manufacturer: String, _ product: String, _ summary: String, _ url: String) {
        self.manufacturer = manufacturer
        self.product = product
        self.summary = summary
        self.url = URL(string: url)!
    }
}

public struct FilamentGuidance: Identifiable, Hashable, Sendable {
    public var id: MaterialCode { material }
    public let material: MaterialCode
    /// Short technical name (not localized: PLA, PETG, PA-CF ...).
    public let displayName: String
    /// Typical drying temperature range across manufacturers (°C).
    public let temperatureRange: ClosedRange<Double>
    /// Typical drying duration range (hours).
    public let durationRangeHours: ClosedRange<Double>
    /// Suggested starting temperature for SpoolDry hardware (already clamped to `deviceMaxCelsius`).
    public let suggestedCelsius: Double
    public let suggestedHours: Double
    /// Relative humidity (%) the chamber should reach for the filament to be considered dry for printing.
    public let humidityTargetPercent: Double
    public let sensitivity: HumiditySensitivity
    /// Localization keys for notes and warnings (strings live in the app's String Catalog).
    public let notesKey: String
    public let warningKeys: [String]
    public let references: [ManufacturerReference]
    public let isFiberFilled: Bool

    /// True when typical guidance exceeds what SpoolDry hardware v1 can reach.
    public var exceedsDeviceLimit: Bool { temperatureRange.lowerBound > FilamentDatabase.deviceMaxCelsius }
    public var needsLongerTimeAtDeviceMax: Bool { temperatureRange.upperBound > FilamentDatabase.deviceMaxCelsius }
}

public enum FilamentDatabase {
    /// Hardware v1 chamber limit (fan and enclosure ratings). Reported by the device in Device Info.
    public static let deviceMaxCelsius: Double = 70
    public static let deviceMinCelsius: Double = 35
    public static let lastVerified: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    // Official references (summaries).
    private static let bambu = "https://wiki.bambulab.com/en/filament-acc/filament/dry-filament"
    private static let prusa = "https://help.prusa3d.com/article/drying-filament_332086"
    private static let polymakerPC = "https://wiki.polymaker.com/the-basics/3d-printing-materials/pc"
    private static let fiberlogy = "https://fiberlogy.com/en/faq-2/"
    private static let x3d = "https://www.3dxtech.com/pages/filament-drying-instructions"
    private static let forwardPA6GF = "https://forward-am.com/wp-content/uploads/2021/12/Ultrafuse_PA6_GF30_TDS_EN_v1.1.pdf"
    private static let raise3dPVA = "https://support.raise3d.com/Pro3-Series/how-to-set-up-pva-filament-for-printing-26-1499.html"

    public static let all: [FilamentGuidance] = [
        g(.pla, "PLA", 45...60, 4...8, 50, 6, 20, .low, warnings: ["warning.lowGlassTransition"], refs: [
            .init("Bambu Lab", "PLA, PLA-CF/GF", "50–60 °C · 8 h (blast oven)", bambu),
            .init("Prusa Research", "Prusament PLA", "45 °C · 6 h", prusa),
            .init("Fiberlogy", "PLA", "50 °C · 4 h", fiberlogy),
            .init("3DXTECH", "PLA", "45 °C · 4 h", x3d),
        ]),
        g(.petg, "PETG", 55...70, 4...8, 65, 6, 20, .moderate, warnings: [], refs: [
            .init("Bambu Lab", "PETG, PETG-CF", "60–70 °C · 8 h (blast oven)", bambu),
            .init("Prusa Research", "Prusament PETG", "55 °C · 6 h", prusa),
            .init("Fiberlogy", "PET-G", "60 °C · 4 h", fiberlogy),
            .init("3DXTECH", "PETG", "65 °C · 4 h", x3d),
        ]),
        g(.abs, "ABS", 60...85, 4...8, 70, 6, 20, .moderate, warnings: [], refs: [
            .init("Bambu Lab", "ABS, ASA", "75–85 °C · 8 h (blast oven)", bambu),
            .init("Fiberlogy", "ABS", "60 °C · 4 h", fiberlogy),
            .init("3DXTECH", "ABS", "80 °C · 4 h", x3d),
        ]),
        g(.asa, "ASA", 65...85, 4...8, 70, 6, 20, .moderate, warnings: [], refs: [
            .init("Bambu Lab", "ABS, ASA", "75–85 °C · 8 h (blast oven)", bambu),
            .init("Prusa Research", "Prusament ASA", "80 °C · 4 h", prusa),
            .init("Fiberlogy", "ASA", "80 °C · 4 h", fiberlogy),
            .init("3DXTECH", "ASA", "80 °C · 4 h", x3d),
        ]),
        g(.tpu, "TPU", 50...75, 4...8, 60, 6, 15, .high, warnings: ["warning.storeSealed"], refs: [
            .init("Bambu Lab", "TPU", "65–75 °C · 8 h (blast oven)", bambu),
            .init("Prusa Research", "TPU / Flex", "60 °C · 4–6 h", prusa),
            .init("3DXTECH", "TPU 85A/95A", "65 °C · 4 h", x3d),
        ]),
        g(.pa, "PA (Nylon)", 70...90, 4...12, 70, 12, 10, .veryHigh, warnings: ["warning.printFromDryBox", "warning.deviceLimitLonger"], refs: [
            .init("Bambu Lab", "PA, PAHT", "75–85 °C · 8–12 h (blast oven)", bambu),
            .init("Fiberlogy", "PA12", "70 °C · 4 h", fiberlogy),
            .init("3DXTECH", "Nylon 12 / Nylon 6", "80 °C · 4 h / 90 °C · 4–6 h", x3d),
        ]),
        g(.pc, "PC", 70...90, 4...8, 70, 8, 15, .high, warnings: ["warning.deviceLimitLonger"], refs: [
            .init("Polymaker", "PC", "70–80 °C · 6–8 h", polymakerPC),
            .init("Bambu Lab", "PC", "75–85 °C · 8 h (blast oven)", bambu),
            .init("Prusa Research", "Prusament PC Blend", "85 °C · 5 h", prusa),
            .init("3DXTECH", "PC (pure)", "120 °C · 4 h+", x3d),
        ]),
        g(.pva, "PVA", 55...85, 4...12, 65, 8, 15, .veryHigh, warnings: ["warning.storeSealed", "warning.printFromDryBox"], refs: [
            .init("Raise3D", "PVA+", "80 °C · 8–12 h", raise3dPVA),
            .init("Bambu Lab", "PVA, BVOH", "75–85 °C · 8–12 h (blast oven)", bambu),
            .init("3DXTECH", "PVA", "65 °C · 4 h", x3d),
        ]),
        g(.bvoh, "BVOH", 50...85, 4...12, 55, 6, 15, .veryHigh, warnings: ["warning.storeSealed"], refs: [
            .init("Fiberlogy", "BVOH", "50 °C · 4 h", fiberlogy),
            .init("Bambu Lab", "PVA, BVOH", "75–85 °C · 8–12 h (blast oven)", bambu),
        ]),
        g(.peek, "PEEK", 120...150, 3...6, 70, 6, 10, .high, warnings: ["warning.highTempDryerRequired"], refs: [
            .init("3DXTECH", "PEEK, PEEK+CF/GF", "150 °C · 3 h", x3d),
        ]),
        g(.pei, "PEI / ULTEM", 130...150, 4...8, 70, 6, 10, .high, warnings: ["warning.highTempDryerRequired"], refs: [
            .init("3DXTECH", "PEI 1010 / PEI 9085", "150 °C · 4–6 h / 130 °C · 4–6 h", x3d),
            .init("Prusa Research", "PEI", "150 °C · 8 h", prusa),
        ]),
        g(.pps, "PPS", 110...140, 4...12, 70, 6, 10, .moderate, warnings: ["warning.highTempDryerRequired"], refs: [
            .init("Bambu Lab", "PPS, PPS-CF/GF", "110–140 °C · 8–12 h (blast oven)", bambu),
            .init("3DXTECH", "PPS", "110 °C · 4 h", x3d),
        ]),
        g(.paCf, "PA-CF", 70...100, 4...12, 70, 12, 10, .veryHigh, fiber: true, warnings: ["warning.printFromDryBox", "warning.deviceLimitLonger", "warning.abrasive"], refs: [
            .init("Bambu Lab", "PA-CF, PAHT-CF", "75–85 °C · 8–12 h (blast oven)", bambu),
            .init("Prusa Research", "Prusament PA11 Carbon Fiber", "90 °C · 6 h", prusa),
            .init("Fiberlogy", "PA12+CF15", "80 °C · 4 h", fiberlogy),
            .init("3DXTECH", "Nylon + CF", "90 °C · 4 h", x3d),
        ]),
        g(.paGf, "PA-GF", 75...100, 4...16, 70, 12, 10, .veryHigh, fiber: true, warnings: ["warning.printFromDryBox", "warning.deviceLimitLonger", "warning.abrasive"], refs: [
            .init("Forward AM (BASF)", "Ultrafuse PA6 GF30", "100 °C · 4–16 h", forwardPA6GF),
            .init("Fiberlogy", "PA12+GF15", "80 °C · 4 h", fiberlogy),
            .init("3DXTECH", "Nylon 6 + GF30", "90 °C · 4 h", x3d),
            .init("Bambu Lab", "PA-GF, PAHT-GF", "75–85 °C · 8–12 h (blast oven)", bambu),
        ]),
        g(.petgCf, "PETG-CF", 60...70, 4...8, 65, 6, 20, .moderate, fiber: true, warnings: ["warning.abrasive"], refs: [
            .init("Bambu Lab", "PETG-CF", "60–70 °C · 8 h (blast oven)", bambu),
            .init("3DXTECH", "PETG + CF", "65 °C · 4 h", x3d),
        ]),
        g(.plaCf, "PLA-CF", 45...60, 4...8, 50, 6, 20, .low, fiber: true, warnings: ["warning.lowGlassTransition", "warning.abrasive"], refs: [
            .init("Bambu Lab", "PLA-CF", "50–60 °C · 8 h (blast oven)", bambu),
        ]),
        g(.pcCf, "PC-CF", 80...120, 4...8, 70, 10, 15, .high, fiber: true, warnings: ["warning.deviceLimitLonger", "warning.abrasive"], refs: [
            .init("Prusa Research", "Prusament PC Blend Carbon Fiber", "90 °C · 4 h", prusa),
            .init("3DXTECH", "PC + CF", "120 °C · 4 h", x3d),
        ]),
        g(.asaCf, "ASA-CF", 65...85, 4...8, 70, 6, 20, .moderate, fiber: true, warnings: ["warning.abrasive"], refs: [
            .init("3DXTECH", "ASA + CF", "80 °C · 4 h", x3d),
            .init("Bambu Lab", "ABS, ASA (incl. fiber-filled)", "75–85 °C · 8 h (blast oven)", bambu),
        ]),
        g(.ppsCf, "PPS-CF", 110...140, 8...12, 70, 6, 10, .moderate, fiber: true, warnings: ["warning.highTempDryerRequired", "warning.abrasive"], refs: [
            .init("Bambu Lab", "PPS-CF/GF", "110–140 °C · 8–12 h (blast oven)", bambu),
        ]),
    ]

    public static func guidance(for material: MaterialCode) -> FilamentGuidance? {
        all.first { $0.material == material }
    }

    private static func g(_ m: MaterialCode, _ name: String, _ temp: ClosedRange<Double>, _ hours: ClosedRange<Double>,
                          _ suggestedC: Double, _ suggestedH: Double, _ rh: Double, _ s: HumiditySensitivity,
                          fiber: Bool = false, warnings: [String], refs: [ManufacturerReference]) -> FilamentGuidance {
        FilamentGuidance(material: m, displayName: name, temperatureRange: temp, durationRangeHours: hours,
                         suggestedCelsius: min(suggestedC, deviceMaxCelsius), suggestedHours: suggestedH,
                         humidityTargetPercent: rh, sensitivity: s, notesKey: "filament.notes.\(m.stableKey)",
                         warningKeys: warnings, references: refs, isFiberFilled: fiber)
    }
}

public extension MaterialCode {
    /// Stable, non-localized identifier used for localization keys and persistence.
    var stableKey: String {
        switch self {
        case .custom: return "custom"
        case .pla: return "pla"
        case .petg: return "petg"
        case .abs: return "abs"
        case .asa: return "asa"
        case .tpu: return "tpu"
        case .pa: return "pa"
        case .pc: return "pc"
        case .pva: return "pva"
        case .bvoh: return "bvoh"
        case .peek: return "peek"
        case .pei: return "pei"
        case .pps: return "pps"
        case .paCf: return "pa_cf"
        case .paGf: return "pa_gf"
        case .petgCf: return "petg_cf"
        case .plaCf: return "pla_cf"
        case .pcCf: return "pc_cf"
        case .asaCf: return "asa_cf"
        case .ppsCf: return "pps_cf"
        }
    }

    /// Technical short name. Material abbreviations are not translated.
    var shortName: String {
        if self == .custom { return "Custom" }
        return FilamentDatabase.guidance(for: self)?.displayName ?? stableKey.uppercased()
    }
}
