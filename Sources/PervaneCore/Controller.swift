import Foundation

public struct Decision: Equatable {
    /// nil = fan sisteme bırakılır.
    public var percent: Double?
    public var profile: String
    public var reason: String
    public var emergency: Bool

    public init(percent: Double?, profile: String, reason: String, emergency: Bool) {
        self.percent = percent
        self.profile = profile
        self.reason = reason
        self.emergency = emergency
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

    public func effectiveProfile(onBattery: Bool, processes: [String]) -> (Profile, String) {
        for rule in config.rules where rule.enabled {
            guard let p = config.profile(named: rule.profile) else { continue }
            switch rule.kind {
            case .battery:
                if onBattery { return (p, "pilde") }
            case .app:
                let needle = rule.match.lowercased()
                if processes.contains(where: { $0.lowercased().contains(needle) }) {
                    return (p, "\(rule.match) çalışıyor")
                }
            }
        }
        let p = config.profile(named: config.activeProfile) ?? Profile(name: "Sistem", mode: .auto)
        return (p, "seçili profil")
    }

    public mutating func decide(temps: Temps, onBattery: Bool, processes: [String]) -> Decision {
        let (profile, reason) = effectiveProfile(onBattery: onBattery, processes: processes)

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
            return Decision(percent: profile.percent(at: held ?? t), profile: profile.name, reason: reason, emergency: false)
        }
    }
}

/// Hedefe doğru adım adım yaklaşır; ani devir sıçramasını önler.
public func ramp(from current: Double, to target: Double, maxStep: Double) -> Double {
    let delta = target - current
    return abs(delta) <= maxStep ? target : current + (delta > 0 ? maxStep : -maxStep)
}
