import AppKit
import PervaneCore
import SwiftUI

/// Kural eklerken seçilebilen, o an açık bir uygulama.
private struct RunningApp: Identifiable {
    let name: String
    /// Servisin süreç listesinde gördüğü ad (çalıştırılabilir dosya adı).
    let process: String
    let icon: NSImage

    var id: String { process }
}

private func runningApps() -> [RunningApp] {
    var seen = Set<String>()
    return NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .compactMap { app -> RunningApp? in
            guard let exec = app.executableURL?.lastPathComponent, seen.insert(exec).inserted else { return nil }
            let icon = (app.icon?.copy() as? NSImage) ?? NSImage()
            icon.size = NSSize(width: 16, height: 16)
            // Çekirdek süreç adını 32 karakterde keser; kural da öyle saklanır.
            return RunningApp(name: app.localizedName ?? exec, process: String(exec.prefix(32)), icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

struct RulesView: View {
    @ObservedObject var model: Model
    let config: Config

    @State private var newMatch = ""
    @State private var apps: [RunningApp] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bir kural tutunca seçili profilin yerine onunki geçer. Yukarıdan aşağı denenir, ilk tutan kazanır.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if config.rules.isEmpty {
                Text("Henüz kural yok.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10).card()
            }
            ForEach(Array(config.rules.enumerated()), id: \.offset) { index, rule in
                row(index, rule)
            }

            HStack(spacing: 6) {
                Menu {
                    ForEach(apps) { app in
                        Button {
                            add(match: app.process)
                        } label: {
                            Image(nsImage: app.icon)
                            Text(app.name)
                        }
                    }
                } label: {
                    Label("Uygulama Ekle", systemImage: "plus.app")
                }
                .fixedSize()
                if !config.rules.contains(where: { $0.kind == .battery }) {
                    Button {
                        model.update { $0.rules.append(Rule(kind: .battery, profile: config.activeProfile)) }
                    } label: {
                        Label("Pil Kuralı", systemImage: "battery.50percent")
                    }
                }
                Spacer()
            }
            HStack(spacing: 6) {
                TextField("ya da süreç adı yaz (ör. com.docker)", text: $newMatch)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTyped)
                Button(action: addTyped) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newMatch.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { apps = runningApps() }
    }

    private func addTyped() {
        let match = newMatch.trimmingCharacters(in: .whitespaces)
        guard !match.isEmpty else { return }
        add(match: match)
        newMatch = ""
    }

    private func add(match: String) {
        guard !config.rules.contains(where: { $0.kind == .app && $0.match.caseInsensitiveCompare(match) == .orderedSame }) else { return }
        model.update { $0.rules.insert(Rule(kind: .app, match: match, profile: config.activeProfile), at: 0) }
    }

    private func icon(for rule: Rule) -> some View {
        Group {
            if rule.kind == .battery {
                Image(systemName: "battery.50percent").foregroundStyle(.orange)
            } else if let app = apps.first(where: { $0.process.range(of: rule.match, options: .caseInsensitive) != nil }) {
                Image(nsImage: app.icon)
            } else {
                Image(systemName: "app.dashed").foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func row(_ index: Int, _ rule: Rule) -> some View {
        HStack(spacing: 8) {
            icon(for: rule)
            VStack(alignment: .leading, spacing: 0) {
                Text(rule.kind == .battery ? "Pilde" : rule.match).lineLimit(1)
                Text(rule.kind == .battery ? "fiş takılı değilken" : "çalışırken").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Picker("", selection: Binding(get: { rule.profile },
                                          set: { v in model.update { $0.rules[index].profile = v } })) {
                ForEach(config.profiles) { Text($0.name).tag($0.name) }
            }
            .labelsHidden()
            .frame(width: 104)
            Toggle("", isOn: Binding(get: { rule.enabled },
                                     set: { v in model.update { $0.rules[index].enabled = v } }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            Menu {
                Button("Yukarı Taşı") { model.update { $0.rules.swapAt(index, index - 1) } }
                    .disabled(index == 0)
                Button("Aşağı Taşı") { model.update { $0.rules.swapAt(index, index + 1) } }
                    .disabled(index >= config.rules.count - 1)
                Divider()
                Button("Kuralı Sil", role: .destructive) { model.update { $0.rules.remove(at: index) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(rule.enabled ? 1 : 0.55)
    }
}
