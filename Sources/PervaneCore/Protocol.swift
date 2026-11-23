import Foundation

public let defaultSocketPath = "/var/run/pervane.sock"

public func socketPath() -> String {
    ProcessInfo.processInfo.environment["PERVANE_SOCKET"] ?? defaultSocketPath
}

public struct Sample: Codable, Equatable {
    public var t: Double
    public var temp: Double
    public var rpm: Double

    public init(t: Double, temp: Double, rpm: Double) {
        self.t = t
        self.temp = temp
        self.rpm = rpm
    }
}

public struct Request: Codable {
    public var cmd: String
    public var profile: String?
    public var config: Config?
    /// Bu andan (epoch saniyesi) yeni geçmiş örnekleri istenir; nil = geçmiş gönderilmez, 0 = hepsi.
    public var since: Double?

    public init(cmd: String, profile: String? = nil, config: Config? = nil, since: Double? = nil) {
        self.cmd = cmd
        self.profile = profile
        self.config = config
        self.since = since
    }
}

public struct Status: Codable, Equatable {
    public var ok: Bool
    public var error: String?
    public var fans: [FanState]
    public var temps: Temps
    public var onBattery: Bool
    public var profile: String
    public var reason: String
    public var emergency: Bool
    /// Servisin istediği devir; nil = sistem yönetiyor.
    public var wantedRPM: Double?
    public var dryRun: Bool
    public var config: Config
    public var history: [Sample]
    /// Eğri %0 verdiği için fan sisteme bırakıldı.
    public var cool: Bool?
    /// Profil menüden elle seçildi ve kuralların önünde.
    public var manualOverride: Bool?
    /// Elle seçim yüzünden bekleyen kural ("pilde → Sessiz"); yoksa nil.
    public var pendingRule: String?

    public init(ok: Bool, error: String? = nil, fans: [FanState], temps: Temps, onBattery: Bool, profile: String,
                reason: String, emergency: Bool, wantedRPM: Double?, dryRun: Bool, config: Config, history: [Sample],
                cool: Bool? = nil, manualOverride: Bool? = nil, pendingRule: String? = nil) {
        self.cool = cool
        self.manualOverride = manualOverride
        self.pendingRule = pendingRule
        self.ok = ok
        self.error = error
        self.fans = fans
        self.temps = temps
        self.onBattery = onBattery
        self.profile = profile
        self.reason = reason
        self.emergency = emergency
        self.wantedRPM = wantedRPM
        self.dryRun = dryRun
        self.config = config
        self.history = history
    }
}

public enum ClientError: Error, CustomStringConvertible {
    case notRunning, badReply, server(String)

    public var description: String {
        switch self {
        case .notRunning: return "Servis çalışmıyor"
        case .badReply: return "Servisten anlaşılmayan yanıt"
        case .server(let m): return m
        }
    }
}

/// Servise tek istek gönderip yanıtı bekler.
public func send(_ request: Request, path: String = socketPath()) throws -> Status {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ClientError.notRunning }
    defer { close(fd) }
    var tv = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var addr = unixAddress(path)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard rc == 0 else { throw ClientError.notRunning }

    var payload = try JSONEncoder().encode(request)
    payload.append(0x0a)
    guard writeAll(fd, payload) else { throw ClientError.notRunning }
    guard let line = readLine(fd, limit: 4 << 20),
          let status = try? JSONDecoder().decode(Status.self, from: line) else { throw ClientError.badReply }
    if !status.ok { throw ClientError.server(status.error ?? "bilinmeyen hata") }
    return status
}

public func unixAddress(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        let bytes = Array(path.utf8.prefix(cap - 1))
        buf.copyBytes(from: bytes)
    }
    return addr
}

public func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    var offset = 0
    while offset < data.count {
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress! + offset, data.count - offset) }
        if n <= 0 { return false }
        offset += n
    }
    return true
}

/// Satır sonuna kadar okur; sınır aşılırsa nil.
public func readLine(_ fd: Int32, limit: Int) -> Data? {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 16384)
    while data.count <= limit {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { return data.isEmpty ? nil : data }
        if let nl = buf[0..<n].firstIndex(of: 0x0a) {
            data.append(contentsOf: buf[0..<nl])
            return data
        }
        data.append(contentsOf: buf[0..<n])
    }
    return nil
}
