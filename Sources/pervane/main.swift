import Foundation
import PervaneCore

let usage = """
pervane: fan kontrolü

  pervane                 durum
  pervane profil <ad>     profili seç (kuralların önüne geçer)
  pervane otomatik        elle seçimi bırak, kurallara dön
  pervane profiller       profilleri ve kuralları göster
  pervane izle            durumu 2 saniyede bir yenile
  pervane json            ham durum (betikler için)
  pervane sensor          servis olmadan doğrudan SMC'den oku
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func request(_ r: Request) -> Status {
    do { return try send(r) } catch { fail("\(error)") }
}

func deg(_ v: Double?) -> String {
    v.map { String(format: "%.0f °C", $0) } ?? "yok"
}

func printStatus(_ s: Status) {
    print("Profil    \(s.profile) (\(s.reason))\(s.dryRun ? "  [kuru çalışma]" : "")")
    if let pending = s.pendingRule { print("Bekleyen  \(pending) (pervane otomatik ile kurala dön)") }
    print("İşlemci   \(deg(s.temps.cpu))   Yonga \(deg(s.temps.soc))   Pil \(deg(s.temps.battery))")
    for (i, f) in s.fans.enumerated() {
        let pct = (f.rpm - f.min) / max(1, f.max - f.min) * 100
        let who = f.manual ? "elle" : "sistem"
        var line = "Fan \(i + 1)     \(Int(f.rpm)) dev/dk (%\(Int(max(0, pct))))  kip: \(who)"
        if let w = s.wantedRPM { line += "  hedef \(Int(w))" }
        else if s.cool == true { line += "  soğuk, sisteme bırakıldı" }
        print(line)
    }
    print("Güç       \(s.onBattery ? "pil" : "adaptör")")
    if s.emergency { print("ACİL DURUM: fan tam güçte") }
}

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first {
case nil, "durum":
    printStatus(request(Request(cmd: "status")))
case "profil":
    guard argv.count >= 2 else { fail(usage) }
    printStatus(request(Request(cmd: "profile", profile: argv.dropFirst().joined(separator: " "))))
case "otomatik":
    printStatus(request(Request(cmd: "auto")))
case "profiller":
    let s = request(Request(cmd: "status"))
    for p in s.config.profiles {
        let mark = p.name == s.config.activeProfile ? "*" : " "
        var detail = p.mode.label
        if p.mode == .curve {
            detail += " (" + p.curve.map { "\(Int($0.temp))°→%\(Int($0.percent))" }.joined(separator: ", ") + ")"
        } else if p.mode == .fixed {
            detail += " %\(Int(p.fixedPercent))"
        }
        print("\(mark) \(p.name): \(detail)")
    }
    for r in s.config.rules {
        let what = r.kind == .battery ? "pilde" : "\"\(r.match)\" çalışırken"
        print("  kural: \(what) → \(r.profile)\(r.enabled ? "" : " (kapalı)")")
    }
case "izle":
    while true {
        print("\u{1B}[2J\u{1B}[H", terminator: "")
        printStatus(request(Request(cmd: "status")))
        Thread.sleep(forTimeInterval: 2)
    }
case "json":
    let s = request(Request(cmd: "status", since: 0))
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try! enc.encode(s), as: UTF8.self))
case "sensor":
    guard let hw = Hardware() else { fail("AppleSMC açılamadı") }
    let t = hw.temps()
    print("İşlemci (performans) \(deg(t.cpuP))\nİşlemci (verimlilik) \(deg(t.cpuE))\nYonga \(deg(t.soc))\nPil \(deg(t.battery))")
    for (i, f) in hw.fans().enumerated() {
        print("Fan \(i + 1): \(Int(f.rpm)) dev/dk, aralık \(Int(f.min))–\(Int(f.max)), \(f.manual ? "elle" : "sistem")")
    }
default:
    print(usage)
}
