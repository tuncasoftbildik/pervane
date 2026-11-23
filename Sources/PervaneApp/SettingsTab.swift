import PervaneCore
import ServiceManagement
import SwiftUI

struct SettingsTab: View {
    @ObservedObject var model: Model
    let s: Status

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "geliştirme"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: Binding(get: { s.config.emergencyTemp },
                                       set: { v in model.update { $0.emergencyTemp = v } }),
                        in: 80...105, step: 1) {
                    HStack {
                        Text("Acil durum eşiği")
                        Spacer()
                        Text("\(Int(s.config.emergencyTemp)) °C").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("Bu sıcaklıkta profil ne olursa olsun fan tam güce çıkar, 8 °C soğuyunca bırakır.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: Binding(get: { s.config.releaseWhenCool },
                                     set: { v in model.update { $0.releaseWhenCool = v } })) {
                    Text("Soğukken fanı sisteme bırak")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Eğri %0 verdiğinde fan en düşük devirde tutulmaz; sistem onu daha da yavaşlatabilir ya da durdurabilir.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 12)

            VStack(alignment: .leading, spacing: 10) {
                Picker("Menü çubuğu", selection: $model.menuStyle) {
                    ForEach(MenuStyle.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    Text("Oturum açılınca başlat")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
            .card(padding: 12)

            HStack {
                Text("Pervane \(version)").font(.caption).foregroundStyle(.secondary)
                Link("GitHub", destination: URL(string: "https://github.com/tuncasoftbildik/pervane")!)
                    .font(.caption)
                Spacer()
                Button("Çık") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Ayarlanamadı: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
