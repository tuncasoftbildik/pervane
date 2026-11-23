import Foundation

public struct Decision: Equatable {
    /// nil = fan sisteme bırakılır.
    public var percent: Double?
    public var profile: String
    public var reason: String
    public var emergency: Bool
    /// Eğri %0 verdiği için fan sisteme bırakıldı.
    public var cool: Bool

    public init(percent: Double?, profile: String, reason: String, emergency: Bool, cool: Bool = false) {
        self.percent = percent
        self.profile = profile
        self.reason = reason
        self.emergency = emergency
        self.cool = cool
    }
}

/// Donanımdan bağımsız karar mantığı: kural seçimi, eğri, histerezis, acil durum.
public struct Controller {
    public var config: Config
    /// Histerezis için tutulan sıcaklık; profil değişince sıfırlanır.
    private var held: Double?
    private var heldProfile: String?
    private var emergencyLatched = false

    public init(config: Config) {
        self.config = config
    }

    /// Menüden elle seçilen profil kuralları ezer; kuralların durumu değişene kadar
    /// (fiş takıldı/çekildi, kurallı uygulama açıldı/kapandı) geçerli kalır.
    public private(set) var manualOverride = false
    /// Son turda tutan kuralın kimliği; değişince elle seçim düşer.
    private var lastRuleKey: String?

    public mutating func selectManually(_ name: String) {
        config.activeProfile = name
        manualOverride = true
    }

    /// Elle seçimi bırakır; tutan kural varsa yeniden o geçerli olur.
    public mutating func clearManual() {
        manualOverride = false
    }

    /// Tutan ilk kural (profil, gerekçe, kural kimliği).
    func matchingRule(onBattery: Bool, processes: [String]) -> (Profile, String, String)? {
        for rule in config.rules where rule.enabled {
            guard let p = config.profile(named: rule.profile) else { continue }
            switch rule.kind {
            case .battery:
                if onBattery { return (p, "pilde", rule.id) }
            case .app:
                if processes.contains(where: { $0.range(of: rule.match, options: .caseInsensitive) != nil }) {
                    return (p, "\(rule.match) çalışıyor", rule.id)
                }
            }
        }
        return nil
    }

    /// Şu an tutan kuralın profili ve gerekçesi; arayüz elle seçimin neyi ezdiğini göstersin diye.
    public func ruleMatch(onBattery: Bool, processes: [String]) -> (profile: String, reason: String)? {
        matchingRule(onBattery: onBattery, processes: processes).map { ($0.0.name, $0.1) }
    }

    private func resolve(_ match: (Profile, String, String)?) -> (Profile, String) {
        let active = config.profile(named: config.activeProfile) ?? Profile(name: "Sistem", mode: .auto)
        if manualOverride { return (active, "elle seçildi") }
        if let (p, reason, _) = match { return (p, reason) }
        return (active, "seçili profil")
    }

    public func effectiveProfile(onBattery: Bool, processes: [String]) -> (Profile, String) {
        resolve(matchingRule(onBattery: onBattery, processes: processes))
    }

    public mutating func decide(temps: Temps, onBattery: Bool, processes: [String]) -> Decision {
        let match = matchingRule(onBattery: onBattery, processes: processes)
        let key = match?.2 ?? "-"
        if let last = lastRuleKey, last != key { manualOverride = false }
        lastRuleKey = key
        let (profile, reason) = resolve(match)

        // Acil durum: eşikte tam güç, 8 °C soğuyana kadar bırakma.
        let hottest = temps.value(for: .hottest)
        if let h = hottest {
            if h >= config.emergencyTemp { emergencyLatched = true }
            else if h <= config.emergencyTemp - 8 { emergencyLatched = false }
        }
        if emergencyLatched {
            return Decision(percent: 100, profile: profile.name, reason: "acil durum: \(Int(hottest ?? 0)) °C", emergency: true)
        }

        switch profile.mode {
        case .auto:
            return Decision(percent: nil, profile: profile.name, reason: reason, emergency: false)
        case .max:
            return Decision(percent: 100, profile: profile.name, reason: reason, emergency: false)
        case .fixed:
            return Decision(percent: profile.fixedPercent, profile: profile.name, reason: reason, emergency: false)
        case .curve:
            // Sensör okunamıyorsa körlemesine sürme, sisteme bırak.
            guard let t = temps.value(for: profile.sensor) else {
                return Decision(percent: nil, profile: profile.name, reason: "sensör okunamadı", emergency: false)
            }
            if heldProfile != profile.name { held = nil; heldProfile = profile.name }
            if let h = held, t < h, t > h - profile.hysteresis {
                // Histerezis bandının içinde: devri indirme.
            } else {
                held = t
            }
            let percent = profile.percent(at: held ?? t)
            // Eğrinin dibinde fanı en düşük devirde tutmak yerine sisteme bırak. Histerezis burada da
            // geçerli: sıcaklık bant kadar düşmeden %0'a inilmez, yani iki kip arasında gidip gelmez.
            if config.releaseWhenCool, percent <= 0 {
                return Decision(percent: nil, profile: profile.name, reason: reason, emergency: false, cool: true)
            }
            return Decision(percent: percent, profile: profile.name, reason: reason, emergency: false)
        }
    }
}

/// Hedefe doğru adım adım yaklaşır; ani devir sıçramasını önler.
public func ramp(from current: Double, to target: Double, maxStep: Double) -> Double {
    let delta = target - current
    return abs(delta) <= maxStep ? target : current + (delta > 0 ? maxStep : -maxStep)
}
