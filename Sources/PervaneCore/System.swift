import Foundation
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
