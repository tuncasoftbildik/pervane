import Foundation
import PervaneCore

// Pervane servisi: fanı süren tek yer. Root olarak launchd altında çalışır.
//   --uid <n>     soket bu kullanıcıya verilir (yalnız o bağlanabilir)
//   --kuru        SMC'ye yazmaz; karar mantığını denemek için
//   --ayar <yol>  ayar dosyası

let args = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let dryRun = args.contains("--kuru")
let ownerUID = option("--uid").flatMap { uid_t($0) }
let configPath = option("--ayar") ?? "/Library/Application Support/Pervane/ayar.json"
let sockPath = socketPath()
let tickSeconds = 2.0
let historyLimit = 900  // 30 dakika

func log(_ message: String) {
    FileHandle.standardError.write(Data("pervaned: \(message)\n".utf8))
}

guard let hw = Hardware() else {
    log("AppleSMC açılamadı")
    exit(1)
}
guard hw.fanCount > 0 else {
    log("bu makinede fan yok")
    exit(1)
}
if !dryRun, getuid() != 0 {
    log("fanı sürmek için root gerekir (denemek için --kuru)")
    exit(1)
}

func loadConfig() -> Config {
    guard let data = FileManager.default.contents(atPath: configPath),
          let c = try? JSONDecoder().decode(Config.self, from: data) else { return .default }
    return c.sanitized()
}

func saveConfig(_ c: Config) {
    let url = URL(fileURLWithPath: configPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? enc.encode(c) else { return }
    do { try data.write(to: url, options: .atomic) } catch { log("ayar yazılamadı: \(error.localizedDescription)") }
}

var controller = Controller(config: loadConfig())
var history: [Sample] = []
var smoothed: Temps?
var processes: [String] = []
var tickCount = 0
var lastDecision = Decision(percent: nil, profile: controller.config.activeProfile, reason: "başlıyor", emergency: false)
var wantedRPM: Double?
/// Son yazdığımız devir; yumuşak geçişin başlangıcı.
var appliedRPM: Double?
var releasing = false

/// Tek tük sıçramaları yutmak için üstel ortalama; yükselişi hızlı, düşüşü yavaş izler.
func smooth(_ new: Double?, _ old: Double?) -> Double? {
    guard let n = new else { return nil }
    guard let o = old else { return n }
    return n > o ? o + (n - o) * 0.6 : o + (n - o) * 0.3
}

func release() {
    guard !dryRun else { return }
    hw.setAllAuto()
}

func tick() {
    guard !releasing else { return }
    let raw = hw.temps()
    smoothed = Temps(cpuP: smooth(raw.cpuP, smoothed?.cpuP), cpuE: smooth(raw.cpuE, smoothed?.cpuE),
                     soc: smooth(raw.soc, smoothed?.soc), battery: smooth(raw.battery, smoothed?.battery))
    if tickCount % 5 == 0 { processes = runningProcessNames() }
    tickCount += 1

    // Acil durum ham değere bakar; ortalama gecikmesin.
    var forDecision = smoothed!
    if let hot = raw.value(for: .hottest), hot >= controller.config.emergencyTemp {
        forDecision = raw
    }
    let decision = controller.decide(temps: forDecision, onBattery: isOnBattery(), processes: processes)
    if decision.profile != lastDecision.profile || decision.emergency != lastDecision.emergency {
        log("profil: \(decision.profile) (\(decision.reason))")
    }
    lastDecision = decision

    let fans = hw.fans()
    if let percent = decision.percent, let first = fans.first {
        let target = first.min + (first.max - first.min) * percent / 100
        // Acil durumda bekleme yok; yoksa tur başına en çok 600 devir.
        let start = appliedRPM ?? first.rpm
        let next = decision.emergency ? target : ramp(from: start, to: target, maxStep: 600)
        wantedRPM = target
        appliedRPM = next
        if !dryRun {
            for (i, fan) in fans.enumerated() {
                let rpm = fan.min + (fan.max - fan.min) * (next - first.min) / max(1, first.max - first.min)
                if !hw.setTarget(fan: i, rpm: rpm.rounded()) { log("fan \(i) yazılamadı") }
            }
        }
    } else {
        wantedRPM = nil
        appliedRPM = nil
        if !dryRun, fans.contains(where: \.manual) { hw.setAllAuto() }
    }

    if let t = raw.value(for: .hottest), let rpm = fans.first?.rpm {
        history.append(Sample(t: Date().timeIntervalSince1970, temp: t, rpm: rpm))
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }
}

func status(error: String? = nil, withHistory: Bool = true) -> Status {
    Status(ok: error == nil, error: error, fans: hw.fans(), temps: hw.temps(), onBattery: isOnBattery(),
           profile: lastDecision.profile, reason: lastDecision.reason, emergency: lastDecision.emergency,
           wantedRPM: wantedRPM, dryRun: dryRun, config: controller.config, history: withHistory ? history : [])
}

func handle(_ req: Request) -> Status {
    switch req.cmd {
    case "status":
        return status()
    case "profile":
        guard let name = req.profile, controller.config.profile(named: name) != nil else {
            return status(error: "Böyle bir profil yok", withHistory: false)
        }
        controller.selectManually(name)
        saveConfig(controller.config)
        tick()
        return status()
    case "config":
        guard let c = req.config else { return status(error: "Ayar eksik", withHistory: false) }
        controller.config = c.sanitized()
        saveConfig(controller.config)
        tick()
        return status()
    default:
        return status(error: "Bilinmeyen komut", withHistory: false)
    }
}

// MARK: Soket

unlink(sockPath)
let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = unixAddress(sockPath)
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard listenFD >= 0, bound == 0, listen(listenFD, 8) == 0 else {
    log("soket açılamadı: \(sockPath)")
    exit(1)
}
// Yalnız sahibi bağlanabilsin: fan ayarı tek kullanıcının işi.
chmod(sockPath, 0o600)
if let uid = ownerUID { chown(sockPath, uid, gid_t.max) }

let acceptSource = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .main)
acceptSource.setEventHandler {
    let fd = accept(listenFD, nil, nil)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var tv = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var noSigpipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

    let reply: Status
    if let line = readLine(fd, limit: 256 << 10), let req = try? JSONDecoder().decode(Request.self, from: line) {
        reply = handle(req)
    } else {
        reply = status(error: "İstek okunamadı", withHistory: false)
    }
    if var out = try? JSONEncoder().encode(reply) {
        out.append(0x0a)
        _ = writeAll(fd, out)
    }
}
acceptSource.resume()

// MARK: Kapanış: fan her durumda sisteme geri verilir.

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        releasing = true
        release()
        unlink(sockPath)
        log("kapanıyor, fan sisteme bırakıldı")
        exit(0)
    }
    src.resume()
    signalSources.append(src)
}

let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: tickSeconds, leeway: .milliseconds(200))
timer.setEventHandler { tick() }
timer.resume()

log("başladı: \(hw.fanCount) fan, soket \(sockPath)\(dryRun ? ", kuru çalışma" : "")")
dispatchMain()
