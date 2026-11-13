import PervaneCore
import SwiftUI

struct RulesView: View {
    @ObservedObject var model: Model
    let config: Config

    @State private var newMatch = ""
    @State private var newProfile = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Otomatik Geçiş").font(.headline)
            ForEach(Array(config.rules.enumerated()), id: \.offset) { index, rule in
                HStack {
                    Toggle(isOn: Binding(get: { rule.enabled },
                                         set: { v in model.update { $0.rules[index].enabled = v } })) {
                        Text(rule.kind == .battery ? "Pilde" : rule.match)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Spacer()
                    Picker("", selection: Binding(get: { rule.profile },
                                                  set: { v in model.update { $0.rules[index].profile = v } })) {
                        ForEach(config.profiles) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Button {
                        model.update { $0.rules.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Uygulama adı", text: $newMatch)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newProfile) {
                    ForEach(config.profiles) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .frame(width: 110)
                Button {
                    let match = newMatch.trimmingCharacters(in: .whitespaces)
                    let profile = newProfile.isEmpty ? config.activeProfile : newProfile
                    model.update { $0.rules.insert(Rule(kind: .app, match: match, profile: profile), at: 0) }
                    newMatch = ""
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(newMatch.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !config.rules.contains(where: { $0.kind == .battery }) {
                Button("Pil Kuralı Ekle") {
                    model.update { $0.rules.append(Rule(kind: .battery, profile: config.activeProfile)) }
                }
                .buttonStyle(.link)
            }
        }
        .onAppear { if newProfile.isEmpty { newProfile = config.activeProfile } }
    }
}
