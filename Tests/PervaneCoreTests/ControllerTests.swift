import XCTest
@testable import PervaneCore

final class ControllerTests: XCTestCase {
    private func temps(_ cpu: Double?) -> Temps {
        Temps(cpuP: cpu, cpuE: nil, soc: nil, battery: nil)
    }

    private func config(active: String = "Eğri", rules: [Rule] = []) -> Config {
        Config(activeProfile: active, profiles: [
            Profile(name: "Sistem", mode: .auto),
            Profile(name: "Eğri", mode: .curve, curve: [.init(50, 0), .init(70, 50), .init(90, 100)], hysteresis: 5),
            Profile(name: "Sabit", mode: .fixed, fixedPercent: 40),
            Profile(name: "Tam", mode: .max),
        ], rules: rules, emergencyTemp: 95)
    }

    func testCurveInterpolatesAndClampsAtEnds() {
        let p = config().profile(named: "Eğri")!
        XCTAssertEqual(p.percent(at: 30), 0)
        XCTAssertEqual(p.percent(at: 60), 25)
        XCTAssertEqual(p.percent(at: 80), 75)
        XCTAssertEqual(p.percent(at: 120), 100)
    }

    func testHysteresisHoldsSpeedUntilTempDropsEnough() {
        var c = Controller(config: config())
        XCTAssertEqual(c.decide(temps: temps(70), onBattery: false, processes: []).percent, 50)
        // 4 °C düştü, bant 5 °C: devir inmez.
        XCTAssertEqual(c.decide(temps: temps(66), onBattery: false, processes: []).percent, 50)
        // 5 °C düştü: iner.
        XCTAssertEqual(c.decide(temps: temps(65), onBattery: false, processes: []).percent, 37.5)
        // Yükseliş anında izlenir.
        XCTAssertEqual(c.decide(temps: temps(80), onBattery: false, processes: []).percent, 75)
    }

    func testEmergencyOverridesAutoAndLatchesUntilCooled() {
        var c = Controller(config: config(active: "Sistem"))
        XCTAssertNil(c.decide(temps: temps(80), onBattery: false, processes: []).percent)
        let hot = c.decide(temps: temps(95), onBattery: false, processes: [])
        XCTAssertEqual(hot.percent, 100)
        XCTAssertTrue(hot.emergency)
        // 8 °C soğumadan bırakmaz.
        XCTAssertTrue(c.decide(temps: temps(90), onBattery: false, processes: []).emergency)
        XCTAssertNil(c.decide(temps: temps(87), onBattery: false, processes: []).percent)
    }

    func testRulesFirstMatchWins() {
        let rules = [
            Rule(kind: .app, match: "Docker", profile: "Tam"),
            Rule(kind: .battery, profile: "Sabit"),
            Rule(kind: .app, match: "kapali", profile: "Tam", enabled: false),
        ]
        let c = Controller(config: config(rules: rules))
        XCTAssertEqual(c.effectiveProfile(onBattery: true, processes: ["com.docker.virtualization"]).0.name, "Tam")
        XCTAssertEqual(c.effectiveProfile(onBattery: true, processes: ["Finder"]).0.name, "Sabit")
        XCTAssertEqual(c.effectiveProfile(onBattery: false, processes: ["kapali"]).0.name, "Eğri")
    }

    func testMissingSensorFallsBackToSystem() {
        var c = Controller(config: config())
        let d = c.decide(temps: temps(nil), onBattery: false, processes: [])
        XCTAssertNil(d.percent)
    }

    func testSanitizeClampsAndDropsBrokenEntries() {
        var raw = config(rules: [Rule(kind: .app, match: "  ", profile: "Tam"), Rule(kind: .battery, profile: "Yok")])
        raw.activeProfile = "Olmayan"
        raw.emergencyTemp = 300
        raw.profiles[1].curve = [.init(200, 500), .init(-5, -20)]
        let c = raw.sanitized()
        XCTAssertEqual(c.activeProfile, "Sistem")
        XCTAssertEqual(c.emergencyTemp, 105)
        XCTAssertEqual(c.profiles[1].curve, [.init(20, 0), .init(105, 100)])
        XCTAssertTrue(c.rules.isEmpty)
    }

    func testRampLimitsStep() {
        XCTAssertEqual(ramp(from: 2000, to: 5000, maxStep: 500), 2500)
        XCTAssertEqual(ramp(from: 2000, to: 1000, maxStep: 500), 1500)
        XCTAssertEqual(ramp(from: 2000, to: 2200, maxStep: 500), 2200)
    }

    func testManualSelectionBeatsBatteryRuleUntilPowerChanges() {
        var c = Controller(config: config(active: "Eğri", rules: [Rule(kind: .battery, profile: "Sabit")]))
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: true, processes: []).profile, "Sabit")
        c.selectManually("Tam")
        let d = c.decide(temps: temps(60), onBattery: true, processes: [])
        XCTAssertEqual(d.profile, "Tam")
        XCTAssertEqual(d.percent, 100)
        XCTAssertEqual(d.reason, "elle seçildi")
        // Adaptöre takıldı: kural düştü, elle seçim de düşer ama seçili profil zaten Tam.
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: false, processes: []).profile, "Tam")
        // Yeniden pile geçince kural tekrar devreye girer.
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: true, processes: []).profile, "Sabit")
    }

    func testManualSelectionMadeOnACDropsWhenUnplugged() {
        var c = Controller(config: config(active: "Eğri", rules: [Rule(kind: .battery, profile: "Sabit")]))
        _ = c.decide(temps: temps(60), onBattery: false, processes: [])
        c.selectManually("Tam")
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: false, processes: []).profile, "Tam")
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: true, processes: []).profile, "Sabit")
    }

    func testCoolCurveReleasesFanToSystemWithHysteresis() {
        var c = Controller(config: config())
        // Eğrinin dibinde (50 °C altı, %0): fan sisteme bırakılır.
        let cold = c.decide(temps: temps(45), onBattery: false, processes: [])
        XCTAssertNil(cold.percent)
        XCTAssertTrue(cold.cool)
        // Isınınca hemen devreye girer.
        let warm = c.decide(temps: temps(54), onBattery: false, processes: [])
        XCTAssertEqual(warm.percent, 10)
        XCTAssertFalse(warm.cool)
        // 50'nin altına indi ama bant (5 °C) dolmadı: bırakmaz, gidip gelmez.
        XCTAssertEqual(c.decide(temps: temps(49.5), onBattery: false, processes: []).percent, 10)
        // Bant doldu: bırakır.
        XCTAssertNil(c.decide(temps: temps(49), onBattery: false, processes: []).percent)
    }

    func testCoolReleaseCanBeTurnedOff() {
        var cfg = config()
        cfg.releaseWhenCool = false
        var c = Controller(config: cfg)
        let d = c.decide(temps: temps(45), onBattery: false, processes: [])
        XCTAssertEqual(d.percent, 0)
        XCTAssertFalse(d.cool)
    }

    func testCurveWithFloorNeverReleases() {
        var cfg = config()
        cfg.profiles[1].curve = [.init(40, 15), .init(80, 100)]
        var c = Controller(config: cfg)
        XCTAssertEqual(c.decide(temps: temps(30), onBattery: false, processes: []).percent, 15)
    }

    func testOldConfigFileWithoutNewFieldsStillLoads() throws {
        let old = """
        {"activeProfile":"Dengeli","emergencyTemp":90,"rules":[{"enabled":true,"kind":"battery","match":"","profile":"Dengeli"}],
         "profiles":[{"curve":[{"percent":0,"temp":45},{"percent":100,"temp":90}],"fixedPercent":40,"hysteresis":4,"mode":"curve","name":"Dengeli","sensor":"cpu"}]}
        """
        let c = try JSONDecoder().decode(Config.self, from: Data(old.utf8))
        XCTAssertEqual(c.activeProfile, "Dengeli")
        XCTAssertEqual(c.emergencyTemp, 90)
        XCTAssertTrue(c.releaseWhenCool)
        XCTAssertNil(c.profiles[0].icon)
        XCTAssertEqual(c.rules.count, 1)
    }

    func testClearManualReturnsToRule() {
        var c = Controller(config: config(active: "Eğri", rules: [Rule(kind: .battery, profile: "Sabit")]))
        _ = c.decide(temps: temps(60), onBattery: true, processes: [])
        c.selectManually("Tam")
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: true, processes: []).profile, "Tam")
        XCTAssertEqual(c.ruleMatch(onBattery: true, processes: [])?.profile, "Sabit")
        c.clearManual()
        XCTAssertEqual(c.decide(temps: temps(60), onBattery: true, processes: []).profile, "Sabit")
    }

    func testSanitizeDropsDuplicateNamesAndBadIcons() {
        var raw = config()
        raw.profiles.append(Profile(name: "Sabit", mode: .max))
        raw.profiles[0].icon = "leaf.fill"
        raw.profiles[1].icon = "kötü simge!"
        let c = raw.sanitized()
        XCTAssertEqual(c.profiles.map(\.name), ["Sistem", "Eğri", "Sabit", "Tam"])
        XCTAssertEqual(c.profiles[0].icon, "leaf.fill")
        XCTAssertNil(c.profiles[1].icon)
    }
}
