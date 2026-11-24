import AppKit
import IOKit.ps
import Foundation
import PervaneCore

/// Menü çubuğunda ne gösterileceği.
enum MenuStyle: String, CaseIterable, Identifiable {
    case icon, temp, tempPercent, tempRPM, tempWatts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icon: return "Yalnız simge"
        case .temp: return "Simge ve sıcaklık"
        case .tempPercent: return "Sıcaklık ve fan yüzdesi"
        case .tempRPM: return "Sıcaklık ve devir"
        case .tempWatts: return "Sıcaklık ve şarj gücü"
        }
    }
}

/// Menü çubuğu etiketinin içeriği. Yalnız değişince yayımlanır; etiket boşuna yeniden çizilmez.
struct MenuTitle: Equatable {
    var text = ""
    /// 0 = normal, 1 = ısındı, 2 = acil durum.
    var level = 0
    var connected = false
}

/// Servisle konuşan ve arayüzün okuduğu durum.
@MainActor
final class Model: ObservableObject {
    /// Panelin gösterdiği durum (geçmiş hariç). Panel kapalıyken güncellenmez.
    @Published var status: Status?
    /// 30 dakikalık geçmiş; servisten yalnız yeni örnekler istenir.
    @Published var history: [Sample] = []
    /// Şarj aleti takılıyken güç akışı; takılı değilse nil. Uygulama kendisi okur, servis gerekmez.
    @Published var power: PowerInfo?
    @Published var title = MenuTitle()
    @Published var error: String?
    @Published var menuStyle: MenuStyle {
        didSet {
            UserDefaults.standard.set(menuStyle.rawValue, forKey: "menuStyle")
            if menuStyle == .tempWatts { updatePower() }
            if let latest { publishTitle(latest) }
        }
    }

    private var latest: Status?
    /// Son fiş takma/çıkarma ya da alet değişikliği anı.
    private var powerChangedAt: Double = 0
    private var powerSource: CFRunLoopSource?
    private var lastAdapterKey = adapterKey()
    private var timer: Timer?
    private var pollCount = 0
    private var inFlight = false
    /// Panel açıldı bildirimi geldi ama pencere henüz görünür olmamış olabilir.
    private var openHint = false

    init(snapshot: Status? = nil) {
        menuStyle = UserDefaults.standard.string(forKey: "menuStyle").flatMap(MenuStyle.init) ?? .temp
        if let snapshot {
            // Ekran görüntüsü kipi: hazır durumla kurulur, servis yoklanmaz.
            var s = snapshot
            history = s.history
            s.history = []
            power = readPower()
            status = s
            latest = s
            publishTitle(s)
            return
        }
        watchPowerSource()
        refresh()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Panel penceresi açık mı? Menü çubuğu öğesinin kendi penceresi sayılmaz.
    private var panelVisible: Bool {
        openHint || (NSApp?.windows.contains { $0.isVisible && !$0.className.contains("StatusBar") } ?? false)
    }

    private func poll() {
        pollCount += 1
        // İpucu yalnız açılış anını köprüler; sonrasında pencerenin kendisine bakılır.
        if openHint, pollCount % 2 == 0 { openHint = false }
        // Panel kapalıyken yalnız menü çubuğu yazısı gerekir: 4 saniyede bir, geçmişsiz.
        if panelVisible || pollCount % 2 == 0 { refresh() }
    }

    private func perform(_ request: Request) {
        Task.detached {
            let result = Result { try send(request) }
            await MainActor.run { self.apply(result) }
        }
    }

    private func apply(_ result: Result<Status, Error>) {
        inFlight = false
        switch result {
        case .success(var s):
            if error != nil { error = nil }
            merge(s.history)
            s.history = []
            latest = s
            // Güç yalnız gösterilecekse okunur: panel açıkken ya da menü çubuğunda isteniyorsa.
            if panelVisible || menuStyle == .tempWatts { updatePower() }
            publishTitle(s)
            if (panelVisible || status == nil), status != s { status = s }
        case .failure(let e):
            error = "\(e)"
            if case ClientError.notRunning = e {
                status = nil
                latest = nil
                if title != MenuTitle() { title = MenuTitle() }
            }
        }
    }

    private func merge(_ new: [Sample]) {
        guard !new.isEmpty else { return }
        let last = history.last?.t ?? 0
        var h = history
        h.append(contentsOf: new.filter { $0.t > last })
        let cutoff = Date().timeIntervalSince1970 - 30 * 60
        if let first = h.firstIndex(where: { $0.t >= cutoff }), first > 0 { h.removeFirst(first) }
        history = h
    }

    private func publishTitle(_ s: Status) {
        var t = MenuTitle(connected: true)
        let temp = s.temps.cpu.map { "\(Int($0.rounded()))°" } ?? "–"
        switch menuStyle {
        case .icon:
            t.text = ""
        case .temp:
            t.text = temp
        case .tempPercent:
            t.text = s.fans.first.map { "\(temp) %\(Int(fanPercent($0).rounded()))" } ?? temp
        case .tempRPM:
            // 50'ye yuvarla: devir her okumada birkaç birim oynar, yazı durmadan değişmesin.
            t.text = s.fans.first.map { "\(temp) \(Int(($0.rpm / 50).rounded()) * 50)" } ?? temp
        case .tempWatts:
            // Tam sayı watt: menü çubuğunda ondalık her okumada oynar.
            t.text = power.flatMap { $0.stale ? nil : $0.inputWatts }.map { "\(temp) \(Int($0.rounded()))W" } ?? temp
        }
        if s.emergency {
            t.level = 2
        } else if let hot = s.temps.value(for: .hottest), hot >= s.config.emergencyTemp - 8 {
            t.level = 1
        }
        if t != title { title = t }
    }

    private func updatePower() {
        var p = readPower()
        // Sürücü tazelemeden önceki değerler eski alete aittir.
        if var q = p, let at = q.updatedAt, at < powerChangedAt {
            q.stale = true
            p = q
        }
        if p != power { power = p }
    }

    /// Fiş takılınca, çıkınca ya da alet değişince hemen haber al.
    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<Model>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { model.powerSourceChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private func powerSourceChanged() {
        // Bildirim pil yüzdesi ya da kalan süre değişince de gelir; yalnız alet değişince işaretle.
        let key = adapterKey()
        guard key != lastAdapterKey else { return updatePower() }
        lastAdapterKey = key
        powerChangedAt = Date().timeIntervalSince1970
        updatePower()
        if let latest { publishTitle(latest) }
    }

    /// Panel açıldı: beklemeden son bilinen durumu göster, sonra tazele.
    func panelOpened() {
        openHint = true
        if let latest, status != latest { status = latest }
        inFlight = false
        refresh()
    }

    func panelClosed() {
        openHint = false
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        // Panel açıkken eksik geçmiş de istenir; kapalıyken geçmiş hiç taşınmaz.
        let since: Double? = panelVisible ? (history.last?.t ?? 0) : nil
        perform(Request(cmd: "status", since: since))
    }

    func select(profile: String) {
        perform(Request(cmd: "profile", profile: profile, since: history.last?.t ?? 0))
    }

    /// Elle seçimi bırakıp kurallara döner.
    func resumeRules() {
        perform(Request(cmd: "auto", since: history.last?.t ?? 0))
    }

    func update(_ change: (inout Config) -> Void) {
        guard var config = status?.config else { return }
        change(&config)
        guard config != status?.config else { return }
        status?.config = config
        perform(Request(cmd: "config", config: config, since: history.last?.t ?? 0))
    }
}

/// Fanın devir aralığındaki yeri, 0–100.
func fanPercent(_ f: FanState) -> Double {
    guard f.max > f.min else { return 0 }
    return min(100, max(0, (f.rpm - f.min) / (f.max - f.min) * 100))
}

/// Takılı aletin kimliği: takılı değilse boş. Değişince ölçüm yeniden beklenir.
func adapterKey() -> String {
    guard let d = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return "" }
    return [kIOPSPowerAdapterWattsKey, kIOPSPowerAdapterIDKey, kIOPSPowerAdapterFamilyKey, "Current", "AdapterVoltage"]
        .map { "\(d[$0] ?? "")" }.joined(separator: "|")
}
