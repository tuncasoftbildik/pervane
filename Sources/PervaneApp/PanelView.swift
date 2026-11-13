import Charts
import PervaneCore
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: Model
    @State private var editing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = model.status {
                header(s)
                HistoryChart(samples: s.history)
                Divider()
                profiles(s)
                if let name = editing, let profile = s.config.profile(named: name) {
                    ProfileEditor(profile: profile, canDelete: s.config.profiles.count > 1) { changed in
                        model.update { c in
                            guard let i = c.profiles.firstIndex(where: { $0.name == name }) else { return }
                            c.profiles[i] = changed
                        }
                    } onDelete: {
                        editing = nil
                        model.update { c in
                            c.profiles.removeAll { $0.name == name }
                            c.rules.removeAll { $0.profile == name }
                        }
                    }
                }
                Divider()
                RulesView(model: model, config: s.config)
                Divider()
                footer(s)
            } else {
                notConnected
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func header(_ s: Status) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.temps.cpu.map { "\(Int($0.rounded())) °C" } ?? "–")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(s.emergency ? .red : .primary)
                Text("İşlemci").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.fans.first.map { "\(Int($0.rpm.rounded()))" } ?? "–")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(s.wantedRPM.map { "dev/dk, hedef \(Int($0))" } ?? "dev/dk, sistem yönetiyor")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func profiles(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Profil").font(.headline)
                Spacer()
                if s.profile != s.config.activeProfile || s.emergency {
                    Text("\(s.profile): \(s.reason)").font(.caption).foregroundStyle(.orange)
                }
            }
            ForEach(s.config.profiles) { p in
                HStack {
                    Button {
                        model.select(profile: p.name)
                    } label: {
                        HStack {
                            Image(systemName: p.name == s.config.activeProfile ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(p.name == s.config.activeProfile ? Color.accentColor : .secondary)
                            Text(p.name)
                            if p.name == s.profile, p.name != s.config.activeProfile {
                                Image(systemName: "bolt.fill").foregroundStyle(.orange).font(.caption)
                            }
                            Spacer()
                            Text(p.mode.label).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        editing = editing == p.name ? nil : p.name
                    } label: {
                        Image(systemName: editing == p.name ? "chevron.up" : "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Yeni Profil") {
                var name = "Profil \(s.config.profiles.count + 1)"
                while s.config.profile(named: name) != nil { name += "+" }
                let base = s.config.profile(named: "Dengeli")?.curve ?? [.init(45, 0), .init(90, 100)]
                model.update { $0.profiles.append(Profile(name: name, mode: .curve, curve: base)) }
                editing = name
            }
            .buttonStyle(.link)
        }
    }

    private func footer(_ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(get: { s.config.emergencyTemp },
                                   set: { v in model.update { $0.emergencyTemp = v } }),
                    in: 80...105, step: 1) {
                Text("Acil durum eşiği: \(Int(s.config.emergencyTemp)) °C")
            }
            HStack {
                Text("Yonga \(s.temps.soc.map { "\(Int($0))°" } ?? "–")  Pil \(s.temps.battery.map { "\(Int($0))°" } ?? "–")  \(s.onBattery ? "pilde" : "adaptörde")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Çık") { NSApplication.shared.terminate(nil) }
            }
            if s.dryRun {
                Text("Kuru çalışma: fana yazılmıyor").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Servis çalışmıyor", systemImage: "bolt.slash").font(.headline)
            Text("Fanı arka plandaki Pervane servisi sürer. Kurmak için Terminal'de:")
                .font(.callout)
            Text("~/Developer/pervane/kur.sh").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            HStack {
                Spacer()
                Button("Çık") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

struct HistoryChart: View {
    let samples: [Sample]

    var body: some View {
        let now = Date().timeIntervalSince1970
        // 30 dakikalık geçmişi ~150 noktaya indir.
        let stride = max(1, samples.count / 150)
        let points = samples.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
        Chart(points, id: \.t) { s in
            LineMark(x: .value("dk", (s.t - now) / 60), y: .value("°C", s.temp))
                .foregroundStyle(.orange)
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: -30...0)
        .chartYScale(domain: 30...105)
        .chartXAxis {
            AxisMarks(values: [-30, -20, -10, 0]) { v in
                AxisGridLine()
                AxisValueLabel { Text(v.as(Int.self) == 0 ? "şimdi" : "\(v.as(Int.self) ?? 0) dk") }
            }
        }
        .frame(height: 90)
    }
}
