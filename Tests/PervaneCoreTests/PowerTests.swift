import XCTest
@testable import PervaneCore

final class PowerTests: XCTestCase {
    func testChargingFromRegistry() throws {
        let p = try XCTUnwrap(PowerInfo(registry: [
            "ExternalConnected": true, "IsCharging": true, "FullyCharged": false, "CurrentCapacity": 64,
            "Amperage": 490, "Voltage": 12067,
            "AdapterDetails": ["Watts": 67],
            "PowerTelemetryData": ["SystemPowerIn": 64816],
        ]))
        XCTAssertEqual(p.inputWatts!, 64.816, accuracy: 0.001)
        XCTAssertEqual(p.batteryWatts!, 5.913, accuracy: 0.001)
        XCTAssertEqual(p.adapterWatts, 67)
        XCTAssertTrue(p.isCharging)
    }

    func testUnpluggedIsNil() {
        XCTAssertNil(PowerInfo(registry: ["ExternalConnected": false, "Amperage": -900, "Voltage": 12000]))
    }

    func testUnsignedNegativeAmperage() throws {
        // -500 mA işaretsiz 64 bit olarak gelirse
        let p = try XCTUnwrap(PowerInfo(registry: [
            "ExternalConnected": true, "Amperage": NSNumber(value: UInt64(bitPattern: -500)), "Voltage": 12000,
            "PowerTelemetryData": ["SystemVoltageIn": 20000, "SystemCurrentIn": 1500],
        ]))
        XCTAssertEqual(p.batteryWatts!, -6, accuracy: 0.001)
        XCTAssertEqual(p.inputWatts!, 30, accuracy: 0.001)
    }

    func testWattText() {
        XCTAssertEqual(wattText(64.8), "65 W")
        XCTAssertEqual(wattText(5.91), "5,9 W")
        XCTAssertEqual(wattText(-6), "6,0 W")
    }
}
