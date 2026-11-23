import Foundation

public struct CurvePoint: Codable, Equatable, Hashable {
    public var temp: Double
    /// 0 = en düşük devir, 100 = en yüksek devir.
    public var percent: Double

    public init(_ temp: Double, _ percent: Double) {
        self.temp = temp
        self.percent = percent
    }
}

public enum FanMode: String, Codable, CaseIterable {
    case auto, fixed, curve, max

    public var label: String {
        switch self {
        case .auto: return "Sistem"
        case .fixed: return "Sabit"
        case .curve: return "Eğri"
        case .max: return "Tam güç"
        }
    }
}

public struct Profile: Codable, Equatable, Identifiable {
    public var name: String
    public var mode: FanMode
    public var fixedPercent: Double
    public var sensor: SensorKind
    public var curve: [CurvePoint]
    /// Sıcaklık bu kadar düşmeden devir indirilmez.
    public var hysteresis: Double
    /// Arayüzde gösterilen SF Symbols adı; nil ise ada ve kipe göre seçilir.
    public var icon: String?

    public var id: String { name }

    public init(name: String, mode: FanMode, fixedPercent: Double = 40, sensor: SensorKind = .cpu,
                curve: [CurvePoint] = [], hysteresis: Double = 4, icon: String? = nil) {
        self.icon = icon
        self.name = name
        self.mode = mode
        self.fixedPercent = fixedPercent
        self.sensor = sensor
        self.curve = curve
        self.hysteresis = hysteresis
    }

    /// Eğriden yüzde hesaplar; uçların dışında uç değer geçerlidir.
    public func percent(at temp: Double) -> Double {
        let pts = curve.sorted { $0.temp < $1.temp }
        guard let first = pts.first, let last = pts.last else { return 0 }
        if temp <= first.temp { return first.percent }
        if temp >= last.temp { return last.percent }
        for (a, b) in zip(pts, pts.dropFirst()) where temp <= b.temp {
            let span = b.temp - a.temp
            return span <= 0 ? b.percent : a.percent + (b.percent - a.percent) * (temp - a.temp) / span
        }
        return last.percent
    }
}

public struct Rule: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case app, battery }

    public var kind: Kind
    /// app kuralında süreç adının içinde aranan metin (büyük/küçük harf ayırmaz).
    public var match: String
    public var profile: String
    public var enabled: Bool

    public var id: String { "\(kind.rawValue):\(match)" }

    public init(kind: Kind, match: String = "", profile: String, enabled: Bool = true) {
        self.kind = kind
        self.match = match
        self.profile = profile
        self.enabled = enabled
    }
}

public struct Config: Codable, Equatable {
    public var activeProfile: String
    public var profiles: [Profile]
    /// Sırayla denenir, ilk tutan kazanır.
    public var rules: [Rule]
    /// Bu sıcaklıkta profil ne olursa olsun fan tam güce çıkar.
    public var emergencyTemp: Double
    /// Eğri %0 verdiğinde fan en düşük devirde tutulmaz, sisteme bırakılır
    /// (sistem soğukken fanı daha da yavaşlatabilir ya da durdurabilir).
    public var releaseWhenCool: Bool

    public init(activeProfile: String, profiles: [Profile], rules: [Rule], emergencyTemp: Double,
                releaseWhenCool: Bool = true) {
        self.activeProfile = activeProfile
        self.profiles = profiles
        self.rules = rules
        self.emergencyTemp = emergencyTemp
        self.releaseWhenCool = releaseWhenCool
    }

    /// Eski ayar dosyalarında olmayan alanlar varsayılanla dolar; dosya çöpe gitmez.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeProfile = try c.decode(String.self, forKey: .activeProfile)
        profiles = try c.decode([Profile].self, forKey: .profiles)
        rules = try c.decode([Rule].self, forKey: .rules)
        emergencyTemp = try c.decode(Double.self, forKey: .emergencyTemp)
        releaseWhenCool = try c.decodeIfPresent(Bool.self, forKey: .releaseWhenCool) ?? true
    }

    public static let `default` = Config(
        activeProfile: "Dengeli",
        profiles: [
            Profile(name: "Sistem", mode: .auto),
            Profile(name: "Sessiz", mode: .curve, curve: [.init(55, 0), .init(75, 25), .init(88, 60), .init(96, 100)], hysteresis: 6),
            Profile(name: "Dengeli", mode: .curve, curve: [.init(45, 0), .init(65, 30), .init(80, 65), .init(90, 100)]),
            Profile(name: "Serin", mode: .curve, curve: [.init(40, 15), .init(55, 45), .init(70, 80), .init(80, 100)], hysteresis: 3),
            Profile(name: "Tam güç", mode: .max),
        ],
        rules: [
            Rule(kind: .app, match: "com.docker", profile: "Serin"),
            Rule(kind: .battery, profile: "Sessiz"),
        ],
        emergencyTemp: 97
    )

    public func profile(named name: String) -> Profile? {
        profiles.first { $0.name == name }
    }

    /// Root servise dışarıdan gelen ayarı güvenli sınırlara çeker.
    public func sanitized() -> Config {
        var c = self
        var seen = Set<String>()
        c.profiles = Array(c.profiles.prefix(32)).map { p in
            var p = p
            p.name = String(p.name.trimmingCharacters(in: .whitespaces).prefix(40))
            p.icon = p.icon.flatMap { icon in
                let ok = icon.count <= 40 && !icon.isEmpty
                    && icon.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
                return ok ? icon : nil
            }
            p.fixedPercent = p.fixedPercent.clamped(0, 100)
            p.hysteresis = p.hysteresis.clamped(0, 15)
            p.curve = Array(p.curve.prefix(12))
                .map { CurvePoint($0.temp.clamped(20, 105), $0.percent.clamped(0, 100)) }
                .sorted { $0.temp < $1.temp }
            if p.mode == .curve, p.curve.isEmpty { p.mode = .auto }
            return p
        }.filter { !$0.name.isEmpty && seen.insert($0.name).inserted }
        if c.profiles.isEmpty { c.profiles = Config.default.profiles }
        let names = Set(c.profiles.map(\.name))
        if !names.contains(c.activeProfile) { c.activeProfile = c.profiles[0].name }
        c.rules = Array(c.rules.prefix(32)).filter {
            names.contains($0.profile) && ($0.kind == .battery || !$0.match.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        c.emergencyTemp = c.emergencyTemp.clamped(80, 105)
        return c
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        isNaN ? lo : Swift.min(hi, Swift.max(lo, self))
    }
}
