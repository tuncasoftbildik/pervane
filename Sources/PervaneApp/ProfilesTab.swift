import Charts
import PervaneCore
import SwiftUI

struct ProfilesTab: View {
    @ObservedObject var model: Model
    let s: Status
    @Binding var editing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(s.config.profiles) { p in
                card(p)
                if editing == p.name {
                    ProfileEditor(profile: p, canDelete: s.config.profiles.count > 1,
                                  taken: Set(s.config.profiles.map(\.name)).subtracting([p.name]),
                                  current: s.temps.value(for: p.sensor),
                                  releaseWhenCool: s.config.releaseWhenCool) { changed in
                        apply(changed, replacing: p.name)
                    } onDelete: {
                        editing = nil
                        model.update { c in
                            c.profiles.removeAll { $0.name == p.name }
                            c.rules.removeAll { $0.profile == p.name }
                        }
                    }
                }
            }
            Button {
                var name = "Profil \(s.config.profiles.count + 1)"
                while s.config.profile(named: name) != nil { name += "+" }
                let base = s.config.profile(named: "Dengeli")?.curve ?? [.init(45, 0), .init(90, 100)]
                model.update { $0.profiles.append(Profile(name: name, mode: .curve, curve: base)) }
                editing = name
            } label: {
                Label("Yeni Profil", systemImage: "plus")
            }
            .buttonStyle(.link)
            .padding(.top, 2)
        }
    }

    /// Ad değiştiyse kurallar ve seçili profil de yeni ada taşınır.
    private func apply(_ changed: Profile, replacing old: String) {
        model.update { c in
            guard let i = c.profiles.firstIndex(where: { $0.name == old }) else { return }
            c.profiles[i] = changed
            guard changed.name != old else { return }
            if c.activeProfile == old { c.activeProfile = changed.name }
            for j in c.rules.indices where c.rules[j].profile == old { c.rules[j].profile = changed.name }
        }
        if changed.name != old { editing = changed.name }
    }

    private func card(_ p: Profile) -> some View {
        let running = p.name == s.profile
        let chosen = p.name == s.config.activeProfile
        return HStack(spacing: 10) {
            Button {
                model.select(profile: p.name)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: p))
                        .font(.system(size: 14))
                        .foregroundStyle(running ? Color.white : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(running ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.14)),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(p.name).fontWeight(chosen ? .semibold : .regular)
                            if running, !chosen {
                                Text("kural").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.orange.opacity(0.2), in: Capsule())
                            }
                            if chosen {
                                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(summary(of: p)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if p.mode == .curve {
                        Sparkline(points: p.curve).frame(width: 58, height: 24)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                editing = editing == p.name ? nil : p.name
            } label: {
                Image(systemName: editing == p.name ? "chevron.up" : "slider.horizontal.3")
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Düzenle")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(running ? 0.75 : 0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ProfileEditor: View {
    let profile: Profile
    let canDelete: Bool
    /// Başka profillerin adları; aynı ada izin verilmez.
    let taken: Set<String>
    /// Profilin sensöründen o anki sıcaklık.
    let current: Double?
    let releaseWhenCool: Bool
    let onChange: (Profile) -> Void
    let onDelete: () -> Void

    @State private var name: String

    init(profile: Profile, canDelete: Bool, taken: Set<String>, current: Double?, releaseWhenCool: Bool,
         onChange: @escaping (Profile) -> Void, onDelete: @escaping () -> Void) {
        self.profile = profile
        self.canDelete = canDelete
        self.taken = taken
        self.current = current
        self.releaseWhenCool = releaseWhenCool
        self.onChange = onChange
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    private func change(_ edit: (inout Profile) -> Void) {
        var p = profile
        edit(&p)
        if p != profile { onChange(p) }
    }

    private func commitName() {
        let new = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        guard !new.isEmpty, !taken.contains(new) else {
            name = profile.name
            return
        }
        change { $0.name = new }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(iconChoices, id: \.self) { icon in
                        Button {
                            change { $0.icon = icon }
                        } label: {
                            Image(systemName: icon)
                        }
                    }
                } label: {
                    Image(systemName: symbol(for: profile)).frame(width: 18)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Simge")
                TextField("Profil adı", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitName)
            }

            Picker("Kip", selection: Binding(get: { profile.mode }, set: { v in
                change { p in
                    p.mode = v
                    if v == .curve, p.curve.isEmpty { p.curve = [.init(45, 0), .init(90, 100)] }
                }
            })) {
                ForEach(FanMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch profile.mode {
            case .fixed:
                HStack {
                    Slider(value: Binding(get: { profile.fixedPercent }, set: { v in change { $0.fixedPercent = v } }),
                           in: 0...100, step: 5)
                    Text("%\(Int(profile.fixedPercent))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            case .curve:
                CurveEditor(points: profile.curve, current: current, releaseWhenCool: releaseWhenCool) { pts in
                    change { $0.curve = pts }
                }
                HStack {
                    Picker("Sensör", selection: Binding(get: { profile.sensor }, set: { v in change { $0.sensor = v } })) {
                        ForEach(SensorKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .frame(width: 150)
                    Spacer()
                    Stepper("Bant \(Int(profile.hysteresis))°",
                            value: Binding(get: { profile.hysteresis }, set: { v in change { $0.hysteresis = v } }),
                            in: 0...15, step: 1)
                        .help("Sıcaklık bu kadar düşmeden devir indirilmez")
                }
                Text("Noktayı sürükle. Boş yere çift tıkla: ekle. Noktaya çift ya da sağ tıkla: sil.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .auto:
                Text("Fan tümüyle sisteme bırakılır.").font(.caption).foregroundStyle(.secondary)
            case .max:
                Text("Fan hep en yüksek devirde döner.").font(.caption).foregroundStyle(.secondary)
            }
            if canDelete {
                Button("Profili Sil", role: .destructive, action: onDelete).buttonStyle(.link)
            }
        }
        .card()
        .onChange(of: profile.name) { _, new in name = new }
    }
}

/// Sürüklenebilir noktalı fan eğrisi: yatay sıcaklık, dikey devir yüzdesi.
struct CurveEditor: View {
    let points: [CurvePoint]
    /// O anki sıcaklık; eğri üzerinde canlı nokta olarak görünür.
    let current: Double?
    let releaseWhenCool: Bool
    let onChange: ([CurvePoint]) -> Void

    @State private var draft: [CurvePoint]?
    /// Sürüklenen noktanın sırası; -1 = boş yere basıldı, sürükleme yok sayılır.
    @State private var dragIndex: Int?
    /// İmlecin son durduğu yer (çizim alanı koordinatı); sağ tık menüsü buna göre çalışır.
    @State private var hoverPoint: CGPoint?

    private let tempRange = 30.0...105.0
    private let grabRadius: CGFloat = 14

    private func value(at temp: Double, in pts: [CurvePoint]) -> Double {
        Profile(name: "", mode: .curve, curve: pts).percent(at: temp)
    }

    var body: some View {
        let shown = (draft ?? points).sorted { $0.temp < $1.temp }
        // Uçların dışında uç değer geçerli; çizgi de grafiğin kenarına kadar uzasın.
        let line = (shown.first.map { [CurvePoint(tempRange.lowerBound, $0.percent)] } ?? []) + shown
            + (shown.last.map { [CurvePoint(tempRange.upperBound, $0.percent)] } ?? [])
        Chart {
            if releaseWhenCool, let first = shown.first, first.percent <= 0, first.temp > tempRange.lowerBound {
                // Bu bölgede fan sisteme bırakılır.
                RectangleMark(xStart: .value("°C", tempRange.lowerBound), xEnd: .value("°C", first.temp),
                              yStart: .value("%", 0), yEnd: .value("%", 100))
                    .foregroundStyle(fanTint.opacity(0.10))
                    .annotation(position: .overlay, alignment: .top) {
                        Text("sistem").font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
                    }
            }
            ForEach(Array(line.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("°C", p.temp), y: .value("%", p.percent))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.03)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(Array(line.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("°C", p.temp), y: .value("%", p.percent))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                PointMark(x: .value("°C", p.temp), y: .value("%", p.percent))
                    .symbolSize(dragIndex == i ? 150 : 90)
                    .annotation(position: p.percent > 70 ? .bottom : .top, spacing: 4) {
                        if dragIndex == i {
                            Text("\(Int(p.temp))° · %\(Int(p.percent))")
                                .font(.caption2).monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
            }
            if let t = current, tempRange.contains(t) {
                RuleMark(x: .value("°C", t))
                    .foregroundStyle(.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("°C", t), y: .value("%", value(at: t, in: shown)))
                    .symbolSize(60)
                    .foregroundStyle(.orange)
            }
        }
        .chartXScale(domain: tempRange)
        .chartYScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: [40, 60, 80, 100]) { v in
            AxisGridLine()
            AxisValueLabel(anchor: .top, collisionResolution: .disabled) { Text("\(v.as(Int.self) ?? 0)°").fixedSize() }
        } }
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in
            AxisGridLine()
            AxisValueLabel { Text("%\(v.as(Int.self) ?? 0)") }
        } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let frame = proxy.plotFrame.map { geo[$0] } ?? .zero
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if dragIndex == nil {
                                // Yalnız bir noktanın üstünden tutulursa sürüklenir; boş yere basmak noktayı ışınlamaz.
                                dragIndex = nearest(to: local(g.startLocation, frame), in: shown, proxy) ?? -1
                            }
                            guard let i = dragIndex, i >= 0, i < shown.count,
                                  abs(g.translation.width) + abs(g.translation.height) > 1.5,
                                  let (t, pct) = values(at: local(g.location, frame), proxy) else { return }
                            var pts = shown
                            // Komşularını geçemez; sıra bozulmaz.
                            let lo = i > 0 ? pts[i - 1].temp + 1 : tempRange.lowerBound
                            let hi = i < pts.count - 1 ? pts[i + 1].temp - 1 : tempRange.upperBound
                            pts[i] = CurvePoint(min(hi, max(lo, t.rounded())), (min(100, max(0, pct)) / 5).rounded() * 5)
                            draft = pts
                        }
                        .onEnded { _ in
                            if let d = draft, d != points.sorted(by: { $0.temp < $1.temp }) { onChange(d) }
                            draft = nil
                            dragIndex = nil
                        })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                        let at = local(tap.location, frame)
                        if let i = nearest(to: at, in: shown, proxy) { remove(i, from: shown) } else { add(at, to: shown, proxy) }
                    })
                    .onContinuousHover { phase in
                        if case .active(let loc) = phase { hoverPoint = local(loc, frame) }
                    }
                    .contextMenu {
                        let hit = hoverPoint.flatMap { nearest(to: $0, in: shown, proxy) }
                        Button("Buraya Nokta Ekle") {
                            if let at = hoverPoint { add(at, to: shown, proxy) }
                        }
                        .disabled(hit != nil || shown.count >= 12)
                        Button("Bu Noktayı Sil") {
                            if let hit { remove(hit, from: shown) }
                        }
                        .disabled(hit == nil || shown.count <= 2)
                    }
            }
        }
        .frame(height: 140)
    }

    private func local(_ p: CGPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: p.x - frame.minX, y: p.y - frame.minY)
    }

    private func values(at p: CGPoint, _ proxy: ChartProxy) -> (Double, Double)? {
        guard let t: Double = proxy.value(atX: p.x), let pct: Double = proxy.value(atY: p.y) else { return nil }
        return (t, pct)
    }

    /// İmlece `grabRadius` içinde en yakın noktanın sırası.
    private func nearest(to p: CGPoint, in pts: [CurvePoint], _ proxy: ChartProxy) -> Int? {
        var best: (Int, CGFloat)?
        for (i, pt) in pts.enumerated() {
            guard let x = proxy.position(forX: pt.temp), let y = proxy.position(forY: pt.percent) else { continue }
            let d = hypot(x - p.x, y - p.y)
            if d <= grabRadius, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func add(_ at: CGPoint, to pts: [CurvePoint], _ proxy: ChartProxy) {
        guard pts.count < 12, let (t, pct) = values(at: at, proxy) else { return }
        let temp = min(tempRange.upperBound, max(tempRange.lowerBound, t.rounded()))
        guard !pts.contains(where: { $0.temp == temp }) else { return }
        onChange((pts + [CurvePoint(temp, (min(100, max(0, pct)) / 5).rounded() * 5)]).sorted { $0.temp < $1.temp })
    }

    private func remove(_ i: Int, from pts: [CurvePoint]) {
        guard pts.count > 2, pts.indices.contains(i) else { return }
        var out = pts
        out.remove(at: i)
        onChange(out)
    }
}
