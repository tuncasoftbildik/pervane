import AppKit
import PervaneCore
import SwiftUI

@main
struct PervaneApp: App {
    @StateObject private var model: Model

    init() {
        // Belgeler için: `Pervane --goruntu dosya.png [--sekme profiller] [--duzenle Dengeli] [--koyu]`
        if let i = CommandLine.arguments.firstIndex(of: "--goruntu"), i + 1 < CommandLine.arguments.count {
            renderScreenshotAndExit(to: CommandLine.arguments[i + 1])
        }
        _model = StateObject(wrappedValue: Model())
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuLabel(title: model.title)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    let title: MenuTitle

    var body: some View {
        Image(nsImage: menuBarSymbol(level: title.level, connected: title.connected))
        if !title.text.isEmpty {
            Text(title.text).monospacedDigit()
        }
    }
}

/// Paneli ekran dışında çizip PNG'ye yazar; ekran kaydı izni gerektirmez.
@MainActor
private func renderScreenshotAndExit(to path: String) -> Never {
    let args = CommandLine.arguments
    func option(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    guard let status = try? send(Request(cmd: "status", since: 0)) else {
        FileHandle.standardError.write(Data("Servis çalışmıyor\n".utf8))
        exit(1)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let dark = args.contains("--koyu")
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

    let tab = option("--sekme").flatMap { name in PanelTab.allCases.first { $0.rawValue == name } } ?? .status
    let root = PanelView(model: Model(snapshot: status), tab: tab, editing: option("--duzenle"))
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = app.appearance
    window.contentView = host
    // Grafikler ilk çizimden sonra oturur.
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { exit(1) }
    exit(0)
}
