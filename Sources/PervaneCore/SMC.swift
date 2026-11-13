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

    public func read(_ key: String) -> Value? {
        var v = smc_val_t()
        guard smc_read(conn, key, &v) == KERN_SUCCESS else { return nil }
        let type = withUnsafeBytes(of: v.type) { String(decoding: $0.prefix(4), as: UTF8.self) }
        let bytes = withUnsafeBytes(of: v.bytes) { Array($0.prefix(Int(v.size))) }
        return Value(type: type, bytes: bytes)
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
        guard let current = read(key) else { return false }
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
        return smc_write(conn, key, &bytes, UInt32(bytes.count)) == KERN_SUCCESS
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
