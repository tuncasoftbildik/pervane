import PervaneCore
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case status = "durum", profiles = "profiller", rules = "kurallar", settings = "ayarlar"

    var id: String { rawValue }
}

struct PanelView: View {
    @ObservedObject var model: Model
    @State private var tab: PanelTab
    @State private var editing: String?

    init(model: Model, tab: PanelTab = .status, editing: String? = nil) {
        self.model = model
        _tab = State(initialValue: tab)
        _editing = State(initialValue: editing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = model.status {
                Picker("", selection: $tab) {
                    Text("Durum").tag(PanelTab.status)
                    Text("Profiller").tag(PanelTab.profiles)
                    Text("Kurallar").tag(PanelTab.rules)
                    Image(systemName: "gearshape").tag(PanelTab.settings)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .status:
                    StatusTab(model: model, s: s)
                case .profiles:
                    ProfilesTab(model: model, s: s, editing: $editing)
                case .rules:
                    RulesView(model: model, config: s.config)
                case .settings:
                    SettingsTab(model: model, s: s)
                }
            } else {
                notConnected
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { model.panelOpened() }
        .onDisappear { model.panelClosed() }
    }

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Servis çalışmıyor", systemImage: "bolt.slash").font(.headline)
            Text("Fanı arka plandaki Pervane servisi sürer. Kurulum için:")
                .font(.callout)
            Link("github.com/tuncasoftbildik/pervane", destination: URL(string: "https://github.com/tuncasoftbildik/pervane#install")!)
                .font(.callout)
            HStack {
                Spacer()
                Button("Çık") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

// MARK: Durum

struct StatusTab: View {
    @ObservedObject var model: Model
    let s: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gauges
            chips
            banner
            HistoryChart(samples: model.history, fan: s.fans.first, emergency: s.config.emergencyTemp)
                .card()
            profilePicker
        }
    }

    private var gauges: some View {
        let temp = s.temps.cpu
        let limit = s.config.emergencyTemp
        let percent = s.fans.isEmpty ? 0 : s.fans.map(fanPercent).reduce(0, +) / Double(s.fans.count)
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                RingGauge(value: ((temp ?? 30) - 30) / max(1, limit - 30),
                          colors: [heatColor(45, limit: limit), heatColor(70, limit: limit), heatColor(limit, limit: limit)]) {
                    VStack(spacing: 0) {
                        Text(temp.map { "\(Int($0.rounded()))°" } ?? "–")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(s.emergency ? Color.red : Color.primary)
                        Text("İşlemci").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(s.emergency ? "acil durum" : "eşik \(Int(limit))°")
                    .font(.caption).foregroundStyle(s.emergency ? Color.red : Color.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                RingGauge(value: percent / 100, colors: [fanTint.opacity(0.55), fanTint]) {
                    VStack(spacing: 0) {
                        Text("%\(Int(percent.rounded()))")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(s.fans.count > 1 ? "\(s.fans.count) fan" : "Fan").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(s.fans.map { grouped($0.rpm) }.joined(separator: " · ") + " dev/dk")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.default, value: temp.map { Int($0.rounded()) })
    }

    private var chips: some View {
        HStack(spacing: 6) {
            Chip(symbol: "cpu", text: "Yonga \(s.temps.soc.map { "\(Int($0.rounded()))°" } ?? "–")")
            Chip(symbol: "battery.75percent", text: "Pil \(s.temps.battery.map { "\(Int($0.rounded()))°" } ?? "–")")
            Chip(symbol: s.onBattery ? "bolt.slash.fill" : "powerplug.fill", text: s.onBattery ? "Pilde" : "Adaptörde",
                 tint: s.onBattery ? .orange : .green)
            Spacer(minLength: 0)
        }
    }

    /// Fanı kimin, neden yönettiğini tek satırda söyler.
    @ViewBuilder private var banner: some View {
        if s.emergency {
            notice("exclamationmark.triangle.fill", .red, "Acil durum: fan tam güçte", nil, nil)
        } else if s.dryRun {
            notice("eye.slash", .orange, "Kuru çalışma: fana yazılmıyor", nil, nil)
        } else if s.profile != s.config.activeProfile {
            notice("bolt.fill", .orange, "\(s.reason.prefix(1).uppercased() + s.reason.dropFirst()): \(s.profile)",
                   "Seçilene dön") { model.select(profile: s.config.activeProfile) }
        } else if let pending = s.pendingRule {
            notice("hand.point.up.left.fill", .secondary, "Elle seçtin. Bekleyen kural: \(pending)",
                   "Kurala dön") { model.resumeRules() }
        } else if s.cool == true {
            notice("snowflake", fanTint, "Soğuk: fan sisteme bırakıldı", nil, nil)
        } else if s.wantedRPM == nil {
            notice("apple.logo", .secondary, "Fanı sistem yönetiyor", nil, nil)
        } else if let wanted = s.wantedRPM {
            notice("target", .secondary, "Hedef \(grouped(wanted)) dev/dk", nil, nil)
        }
    }

    private func notice(_ symbol: String, _ tint: Color, _ text: String, _ action: String?,
                        _ run: (() -> Void)?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action, let run {
                Button(action, action: run).buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var profilePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(s.config.profiles) { p in
                    let running = p.name == s.profile
                    let chosen = p.name == s.config.activeProfile
                    Button {
                        model.select(profile: p.name)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: symbol(for: p)).font(.system(size: 15)).frame(height: 18)
                            Text(p.name).font(.caption2).lineLimit(1)
                        }
                        .frame(width: 60, height: 48)
                        .foregroundStyle(running ? Color.white : Color.primary)
                        .background(running ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.45)),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: chosen && !running ? 1.5 : 0))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(summary(of: p))
                }
            }
        }
    }
}
