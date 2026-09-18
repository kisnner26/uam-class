import Foundation

/// Respuesta de un PageMethod: envuelve el valor en {"d": ...}.
struct AjaxD<T: Decodable>: Decodable {
    let d: T
}

/// Estado del portal CLASS observado en el response del login.
enum ClassPortalStatus: Equatable {
    case ok
    case badCredentials
    case portalLocked      // patrón 0_N_…
    case wrongPortal
    case adFailed(String)
    case unknown(String)
}
