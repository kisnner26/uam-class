import Foundation

enum AppConfig {
    /// Instancias de Moodle disponibles en UAM.
    /// - grado:    Pregrado (la mayoría de estudiantes con CIF típico).
    /// - lc:       Language Center.
    /// - posgrado: Programas de posgrado (dominio distinto).
    enum MoodleInstance: String, CaseIterable, Identifiable {
        case grado, lc, posgrado
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .grado:    return "Grado"
            case .lc:       return "Language Center"
            case .posgrado: return "Posgrado"
            }
        }
        var baseURL: URL {
            switch self {
            case .grado:    return URL(string: "https://uamvirtual.uam.edu.ni/grado/")!
            case .lc:       return URL(string: "https://uamvirtual.uam.edu.ni/lc/")!
            case .posgrado: return URL(string: "https://uamvirtualposgrado.uam.edu.ni/")!
            }
        }
    }

    /// Instancia de Moodle por defecto (la más común). Podés cambiarla en runtime
    /// desde el picker que agrega la app en el LoginView de Moodle.
    static let defaultMoodleInstance: MoodleInstance = .grado

    /// Compatibilidad con código previo — ruta base de Moodle activa.
    static var moodleBaseURL: URL { defaultMoodleInstance.baseURL }

    /// Base URL de CLASS Portales (WebForms/PageMethods).
    static let classPortalBaseURL = URL(string: "https://uvirtual.uam.edu.ni:442/uvirtual/")!

    /// Service shortname registrado en Moodle para el móvil.
    static let moodleService = "moodle_mobile_app"

    /// Keychain identifiers
    static let keychainService = "com.kisnner.uamclass"
    static let keychainMoodleTokenAccount = "moodle_token"
    static let keychainCIFAccount = "cif"

    /// Rate limiting suave para no martillar servers UAM.
    static let minRequestIntervalMs: Int = 400
}
