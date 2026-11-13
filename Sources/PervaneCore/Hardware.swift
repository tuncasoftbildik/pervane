import Foundation

public struct FanState: Codable, Equatable {
    public var rpm: Double
    public var min: Double
    public var max: Double
    public var target: Double
    public var manual: Bool

    public init(rpm: Double, min: Double, max: Double, target: Double, manual: Bool) {
        self.rpm = rpm
        self.min = min
        self.max = max
        self.target = target
        self.manual = manual
    }
}

public struct Temps: Codable, Equatable {
    /// Performans çekirdeklerinin en sıcağı.
    public var cpuP: Double?
    /// Verimlilik çekirdeklerinin en sıcağı.
    public var cpuE: Double?
    public var soc: Double?
    public var battery: Double?

    public init(cpuP: Double?, cpuE: Double?, soc: Double?, battery: Double?) {
        self.cpuP = cpuP
        self.cpuE = cpuE
        self.soc = soc
        self.battery = battery
    }

    public var cpu: Double? { [cpuP, cpuE].compactMap { $0 }.max() }

    public func value(for sensor: SensorKind) -> Double? {
        switch sensor {
        case .cpu: return cpu
        case .soc: return soc
        case .battery: return battery
        case .hottest: return [cpuP, cpuE, soc].compactMap { $0 }.max()
        }
    }
}

public enum SensorKind: String, Codable, CaseIterable {
    case cpu, soc, battery, hottest

    public var label: String {
        switch self {
        case .cpu: return "İşlemci"
        case .soc: return "Yonga"
        case .battery: return "Pil"
        case .hottest: return "En sıcak"
        }
    }
}

/// Fan ve sıcaklık anahtarlarını bulur, okur, yazar.
public final class Hardware {
    public let smc: SMC
    public let fanCount: Int
    private let pKeys: [String]
    private let eKeys: [String]
    private let socKeys: [String]
    private let batteryKeys: [String]
    /// Eski Apple Silicon sürümlerinde elle kontrolün kilidini açan anahtar; yoksa nil.
    private let hasFtst: Bool

    public init?() {
        guard let smc = SMC() else { return nil }
        self.smc = smc
        fanCount = Int(smc.number("FNum") ?? 0)
        hasFtst = smc.read("Ftst") != nil

        let tKeys = smc.allKeys().filter { $0.hasPrefix("T") && smc.read($0)?.type == "flt " }
        func pick(_ pattern: String) -> [String] {
            tKeys.filter { $0.range(of: pattern, options: .regularExpression) != nil }
        }
        // macOS 27 / M1: Tp2a…Tp9a ham çekirdek sıcaklığı (IOHID "pACC MTR" ile aynı değer).
        var p = pick("^Tp[0-9a-f]a$"), e = pick("^Te[0-9a-f]a$")
        if p.isEmpty { p = pick("^Tp[0-9][0-9A-Za-z]$") }  // eski adlandırma: Tp01, Tp05…
        if p.isEmpty { p = pick("^TC[0-9][A-Z]$") }        // Intel
        if e.isEmpty { e = pick("^Te[0-9][0-9A-Za-z]$") }
        pKeys = p
        eKeys = e
        socKeys = pick("^Ts[0-9a-f]a$")
        batteryKeys = pick("^TB[0-9]T$")
    }

    private func hottest(_ keys: [String]) -> Double? {
        keys.compactMap { smc.number($0) }.filter { $0 > 1 && $0 < 130 }.max()
    }

    public func temps() -> Temps {
        Temps(cpuP: hottest(pKeys), cpuE: hottest(eKeys), soc: hottest(socKeys), battery: hottest(batteryKeys))
    }

    public func fans() -> [FanState] {
        (0..<fanCount).compactMap { i in
            guard let rpm = smc.number("F\(i)Ac"),
                  let lo = smc.number("F\(i)Mn"),
                  let hi = smc.number("F\(i)Mx") else { return nil }
            return FanState(rpm: rpm, min: lo, max: hi,
                            target: smc.number("F\(i)Tg") ?? 0,
                            manual: (smc.number("F\(i)Md") ?? 0) != 0)
        }
    }

    /// Fanı elle moda alıp hedef devri yazar.
    @discardableResult
    public func setTarget(fan i: Int, rpm: Double) -> Bool {
        if hasFtst, smc.number("Ftst") != 1 { smc.write("Ftst", 1) }
        if smc.number("F\(i)Md") != 1, !smc.write("F\(i)Md", 1) { return false }
        return smc.write("F\(i)Tg", rpm)
    }

    /// Fanı sisteme geri verir.
    @discardableResult
    public func setAuto(fan i: Int) -> Bool {
        let ok = smc.number("F\(i)Md") == 0 || smc.write("F\(i)Md", 0)
        if hasFtst, smc.number("Ftst") != 0 { smc.write("Ftst", 0) }
        return ok
    }

    public func setAllAuto() {
        for i in 0..<fanCount { setAuto(fan: i) }
    }
}
