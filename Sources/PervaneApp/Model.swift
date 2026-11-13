import Foundation
import PervaneCore

/// Servisle konuşan ve arayüzün okuduğu durum.
@MainActor
final class Model: ObservableObject {
    @Published var status: Status?
    @Published var error: String?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func perform(_ request: Request) {
        Task.detached {
            let result = Result { try send(request) }
            await MainActor.run {
                switch result {
                case .success(let s):
                    self.status = s
                    self.error = nil
                case .failure(let e):
                    self.error = "\(e)"
                    if case ClientError.notRunning = e { self.status = nil }
                }
            }
        }
    }

    func refresh() {
        perform(Request(cmd: "status"))
    }

    func select(profile: String) {
        perform(Request(cmd: "profile", profile: profile))
    }

    func update(_ change: (inout Config) -> Void) {
        guard var config = status?.config else { return }
        change(&config)
        status?.config = config
        perform(Request(cmd: "config", config: config))
    }

    var menuTitle: String {
        guard let s = status, let fan = s.fans.first else { return "–" }
        let temp = s.temps.cpu.map { "\(Int($0.rounded()))°" } ?? "–"
        return "\(temp) \(Int(fan.rpm.rounded()))"
    }
}
