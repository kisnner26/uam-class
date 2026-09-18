import Foundation
import WatchConnectivity
import Combine

/// Puente iPhone → Watch. Cada vez que el horario local cambia (lo cargaste,
/// lo editaste, se sembró el de la Mac la primera vez) se lo manda al reloj
/// con `updateApplicationContext`: siempre gana el último estado, y si el
/// reloj no está alcanzable en ese momento lo recibe apenas se conecte —
/// no hace falta que la app del reloj esté abierta.
@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    private var cancellable: AnyCancellable?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        cancellable = LocalStore.shared.$schedule
            .dropFirst(0)
            .sink { [weak self] slots in
                self?.send(slots)
            }
    }

    func send(_ slots: [ClassSlot]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(slots) else { return }
        try? WCSession.default.updateApplicationContext(["schedule": data])
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.send(LocalStore.shared.schedule)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// El reloj pide una actualización explícita (por ejemplo, al abrir la
    /// app por primera vez, antes de que el iPhone haya cambiado nada).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            let slots = LocalStore.shared.schedule
            let data = (try? JSONEncoder().encode(slots)) ?? Data()
            replyHandler(["schedule": data])
        }
    }
}
