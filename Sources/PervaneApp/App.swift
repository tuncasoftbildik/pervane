import SwiftUI

@main
struct PervaneApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(systemName: model.status?.emergency == true ? "exclamationmark.triangle.fill" : "fan")
            Text(model.menuTitle).monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
