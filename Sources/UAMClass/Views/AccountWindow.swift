import SwiftUI

/// Ventana de una cuenta secundaria.
///
/// La clave de que dos cuentas funcionen a la vez está acá: el `AppState` se
/// crea con `@StateObject` DENTRO de la ventana, así que cada ventana tiene su
/// propio estado, su propio `MoodleClient` (con su token) y su propio cache.
/// Si compartieran el `AppState` de la app, abrir la segunda cuenta desconectaría
/// a la primera — que es exactamente lo que hacía el "cambio de cuenta".
struct AccountWindow: View {
    static let sceneID = "uamclass.account"

    let accountID: String?

    @StateObject private var state = AppState()
    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        Group {
            if let accountID {
                RootView()
                    .environmentObject(state)
                    .task(id: accountID) {
                        await state.bootstrapWindow(accountID: accountID)
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: .init("UAMClass.OpenPalette"))) { _ in
                        // Solo la ventana de teclado responde al atajo global.
                        if NSApp.keyWindow?.isKeyWindow == true {
                            state.showCommandPalette = true
                        }
                    }
            } else {
                EmptyState(icon: "person.crop.circle.badge.questionmark",
                           title: "Cuenta no encontrada",
                           subtitle: "Esta ventana quedó sin cuenta asociada. Cerrala y volvé a abrirla desde el selector de cuentas.")
                    .environmentObject(prefs)
            }
        }
        .navigationTitle(windowTitle)
    }

    /// El título distingue las ventanas en Mission Control y en el menú Ventana.
    private var windowTitle: String {
        guard let id = accountID,
              let account = AccountStore.shared.accounts.first(where: { $0.id == id })
        else { return "UAM Class" }
        return "\(account.displayName) · \(account.instance.displayName)"
    }
}
