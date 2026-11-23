import CSMC
import Foundation

/// AppleSMC'ye tipli erişim. Okuma yetkisiz, yazma root ister.
public final class SMC {
    private var conn: io_connect_t = 0

    public init?() {
        guard smc_open(&conn) == KERN_SUCCESS else { return nil }
    }

    deinit { smc_close(conn) }

    public struct Value {
        public let type: String
        public let bytes: [UInt8]
    }

    /// Anahtarın boyutu ve tipi sabittir; bir kez sorulur.
    private var infoCache: [String: (size: UInt32, type: String)] = [:]

    private func info(_ key: String) -> (size: UInt32, type: String)? {
        if let hit = infoCache[key] { return hit }
        var size: UInt32 = 0
        var type = [CChar](repeating: 0, count: 5)
        guard smc_key_info(conn, key, &size, &type) == KERN_SUCCESS, size <= 32 else { return nil }
        let entry = (size: size, type: String(cString: type))
        infoCache[key] = entry
        return entry
    }

    public func read(_ key: String) -> Value? {
        guard let i = info(key) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard smc_read_raw(conn, key, i.size, &bytes) == KERN_SUCCESS else { return nil }
        return Value(type: i.type, bytes: Array(bytes.prefix(Int(i.size))))
    }

    public func number(_ key: String) -> Double? {
        guard let v = read(key) else { return nil }
        switch v.type {
        case "flt ":
            guard v.bytes.count == 4 else { return nil }
            return Double(v.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "fpe2":  // Intel: 14.2 sabit nokta, büyük uçlu
            guard v.bytes.count == 2 else { return nil }
            return Double(UInt16(v.bytes[0]) << 8 | UInt16(v.bytes[1])) / 4
        case "ui8 ":
            return v.bytes.first.map(Double.init)
        case "ui16":
            guard v.bytes.count == 2 else { return nil }
            return Double(UInt16(v.bytes[0]) << 8 | UInt16(v.bytes[1]))
        default:
            return nil
        }
    }

    /// Anahtarın kendi tipine göre kodlayıp yazar.
    @discardableResult
    public func write(_ key: String, _ value: Double) -> Bool {
        guard let current = info(key) else { return false }
        var bytes: [UInt8]
        switch current.type {
        case "flt ":
            bytes = withUnsafeBytes(of: Float(value)) { Array($0) }
        case "fpe2":
            let raw = UInt16(max(0, min(16383, value)) * 4)
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        case "ui8 ":
            bytes = [UInt8(max(0, min(255, value)))]
        case "ui16":
            let raw = UInt16(max(0, min(65535, value)))
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        default:
            return false
        }
        guard bytes.count == Int(current.size) else { return false }
        return smc_write_raw(conn, key, &bytes, UInt32(bytes.count)) == KERN_SUCCESS
    }

    public func allKeys() -> [String] {
        var count: UInt32 = 0
        guard smc_key_count(conn, &count) == KERN_SUCCESS else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        var buf = [CChar](repeating: 0, count: 5)
        for i in 0..<count where smc_key_at(conn, i, &buf) == KERN_SUCCESS {
            keys.append(String(cString: buf))
        }
        return keys
    }
}
