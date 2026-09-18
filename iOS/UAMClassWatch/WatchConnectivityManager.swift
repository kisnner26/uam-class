import Foundation
import WatchConnectivity

/// Puente Watch ← iPhone. Guarda el último horario recibido en el propio
/// UserDefaults del reloj (para que sobreviva sin el teléfono cerca) y
/// replanifica los avisos de clase cada vez que llega uno nuevo.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set) var schedule: [ClassSlot] = []
    @Published private(set) var lastSyncedAt: Date?

    private let scheduleKey = "UAMClassWatch.schedule"
    private let syncedAtKey = "UAMClassWatch.lastSyncedAt"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: scheduleKey),
           let decoded = try? JSONDecoder().decode([ClassSlot].self, from: data) {
            schedule = decoded
        }
        lastSyncedAt = UserDefaults.standard.object(forKey: syncedAtKey) as? Date
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Le pide al iPhone el horario actual (por si el reloj arranca antes de
    /// que el teléfono haya mandado nada por su cuenta).
    private func requestFromPhone() {
        guard WCSession.default.isReachable || WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage([:], replyHandler: { [weak self] reply in
            guard let data = reply["schedule"] as? Data else { return }
            Task { @MainActor in self?.apply(data) }
        }, errorHandler: nil)
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode([ClassSlot].self, from: data) else { return }
        schedule = decoded
        lastSyncedAt = Date()
        UserDefaults.standard.set(data, forKey: scheduleKey)
        UserDefaults.standard.set(lastSyncedAt, forKey: syncedAtKey)
        NotificationPlanner.reschedule(for: decoded)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if self.schedule.isEmpty {
                self.requestFromPhone()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["schedule"] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }
}
