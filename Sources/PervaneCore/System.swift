import Foundation
import IOKit
import IOKit.ps

public func isOnBattery() -> Bool {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() else { return false }
    return (type as String) == kIOPMBatteryPowerKey
}

/// Çalışan süreçlerin adları (tekrarsız).
public func runningProcessNames() -> [String] {
    // Önce sayıyı sor; sabit boyutlu tampon kalabalık sistemde listeyi keserdi.
    let count = Int(proc_listallpids(nil, 0))
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: count + 64)
    let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard n > 0 else { return [] }
    var names = Set<String>()
    var buf = [CChar](repeating: 0, count: 256)
    for pid in pids.prefix(Int(n)) where pid > 0 {
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 { names.insert(String(cString: buf)) }
    }
    return Array(names)
}

/// Şarj aleti takılıyken güç akışı. Değerler watt; okunamayan alan nil.
public struct PowerInfo: Equatable, Sendable {
    /// Adaptörden sisteme giren güç (şarj aletinin o an verdiği).
    public var inputWatts: Double?
    /// Pile giren (+) ya da pilden çekilen (−) güç.
    public var batteryWatts: Double?
    /// Şarj aletinin etiket gücü (67 W gibi).
    public var adapterWatts: Double?
    public var isCharging: Bool
    public var fullyCharged: Bool
    public var percent: Int?
    /// Pil sürücüsünün değerleri son tazelediği an (Unix sn). Sürücü dakikada bir tazeler.
    public var updatedAt: Double?
    /// Değerler son fiş değişikliğinden eski: alet değişti, ölçüm henüz gelmedi.
    public var stale = false

    public init(inputWatts: Double? = nil, batteryWatts: Double? = nil, adapterWatts: Double? = nil,
                isCharging: Bool = false, fullyCharged: Bool = false, percent: Int? = nil) {
        self.inputWatts = inputWatts
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
        self.isCharging = isCharging
        self.fullyCharged = fullyCharged
        self.percent = percent
    }
}

/// AppleSmartBattery kaydından şarj gücünü okur; root gerekmez. Şarj aleti takılı değilse nil.
public func readPower() -> PowerInfo? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
    guard var info = PowerInfo(registry: dict) else { return nil }
    // Aletin gücünü güç kaynağı API'sinden al: fiş olayında hemen güncellenir, kayıt dakikada bir.
    if let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
       let w = (details[kIOPSPowerAdapterWattsKey] as? NSNumber)?.doubleValue, w > 0 {
        info.adapterWatts = w
    }
    return info
}

extension PowerInfo {
    /// Kayıt sözlüğünden kurulur (testte elle verilebilsin diye ayrı).
    public init?(registry dict: [String: Any]) {
        func num(_ any: Any?) -> NSNumber? { any as? NSNumber }
        guard num(dict["ExternalConnected"])?.boolValue == true else { return nil }
        self.init()
        let telemetry = dict["PowerTelemetryData"] as? [String: Any]
        if let mw = num(telemetry?["SystemPowerIn"])?.doubleValue, mw > 0 {
            inputWatts = mw / 1000
        } else if let mv = num(telemetry?["SystemVoltageIn"])?.doubleValue,
                  let ma = num(telemetry?["SystemCurrentIn"])?.doubleValue, mv > 0, ma > 0 {
            inputWatts = mv * ma / 1_000_000
        }
        // Amperage işaretlidir; bazı sürümlerde işaretsiz 64 bit gelir, int64Value bit desenini korur.
        if let ma = num(dict["Amperage"])?.int64Value, let mv = num(dict["Voltage"])?.doubleValue, mv > 0 {
            batteryWatts = Double(ma) * mv / 1_000_000
        }
        let adapter = dict["AdapterDetails"] as? [String: Any]
        if let w = num(adapter?["Watts"])?.doubleValue, w > 0 { adapterWatts = w }
        isCharging = num(dict["IsCharging"])?.boolValue ?? false
        fullyCharged = num(dict["FullyCharged"])?.boolValue ?? false
        percent = num(dict["CurrentCapacity"])?.intValue
        updatedAt = num(dict["UpdateTime"])?.doubleValue
    }
}

/// "64,8 W" biçimi; 10 W üstünde tam sayı.
public func wattText(_ w: Double) -> String {
    let v = abs(w)
    let s = v >= 10 ? "\(Int(v.rounded()))" : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    return "\(s) W"
}
