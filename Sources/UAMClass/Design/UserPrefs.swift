import SwiftUI
import Combine

/// Preferencias centrales de personalización. Todo se persiste en UserDefaults
/// y las views se suscriben vía @EnvironmentObject.
@MainActor
final class UserPrefs: ObservableObject {
    static let shared = UserPrefs()

    private let ud = UserDefaults.standard

    // MARK: Accent tint

    @Published var tintIndex: Int {
        didSet { ud.set(tintIndex, forKey: "UAMClass.tintIndex") }
    }

    /// Sonidos de interfaz. Lee y escribe la misma clave que consulta
    /// `SoundKit`, que no puede depender de este objeto porque lo llaman desde
    /// estilos de botón sin acceso al entorno.
    @Published var sounds: Bool {
        didSet { ud.set(sounds, forKey: "UAMClass.sounds") }
    }

    // Celestes de la consola. El primero es el color institucional de la UAM;
    // los demás son variaciones del mismo matiz, para que cambiar de tinte no
    // rompa la identidad.
    static let tintPresets: [TintPreset] = [
        TintPreset(name: "UAM",       hex: 0x0A85A3),
        TintPreset(name: "Laguna",    hex: 0x066B85),
        TintPreset(name: "Cielo",     hex: 0x18B8D0),
        TintPreset(name: "Turquesa",  hex: 0x3AA6A0),
        TintPreset(name: "Índigo",    hex: 0x4A7FB5),
        TintPreset(name: "Menta",     hex: 0x49AE8A)
    ]

    var tint: Color {
        let idx = max(0, min(Self.tintPresets.count - 1, tintIndex))
        return Self.tintPresets[idx].color
    }

    // MARK: Density

    enum Density: String, CaseIterable, Identifiable {
        case compact, comfortable
        var id: String { rawValue }
        var label: String { self == .compact ? "Compacto" : "Cómodo" }
    }

    @Published var density: Density {
        didSet { ud.set(density.rawValue, forKey: "UAMClass.density") }
    }

    var pad: CGFloat { density == .compact ? Space.sm : Space.md }
    var padLarge: CGFloat { density == .compact ? Space.md : Space.lg }
    var gap: CGFloat { density == .compact ? 8 : 12 }
    var gapLarge: CGFloat { density == .compact ? 16 : 24 }

    // MARK: Glass style

    enum Glass: String, CaseIterable, Identifiable {
        case solid, subtle, glass
        var id: String { rawValue }
        var label: String {
            switch self {
            case .solid:  return "Sólido"
            case .subtle: return "Sutil"
            case .glass:  return "Vidrio"
            }
        }
    }

    @Published var glass: Glass {
        didSet { ud.set(glass.rawValue, forKey: "UAMClass.glass") }
    }

    // MARK: Dashboard widgets

    @Published var dashboardWidgets: [DashboardWidget] {
        didSet {
            if let data = try? JSONEncoder().encode(dashboardWidgets) {
                ud.set(data, forKey: "UAMClass.dashboardWidgets")
            }
        }
    }

    // MARK: Init

    private init() {
        self.tintIndex = ud.object(forKey: "UAMClass.tintIndex") as? Int ?? 0
        self.sounds = ud.object(forKey: "UAMClass.sounds") as? Bool ?? true
        let densRaw = ud.string(forKey: "UAMClass.density") ?? "comfortable"
        self.density = Density(rawValue: densRaw) ?? .comfortable
        let glassRaw = ud.string(forKey: "UAMClass.glass") ?? "subtle"
        self.glass = Glass(rawValue: glassRaw) ?? .subtle

        if let data = ud.data(forKey: "UAMClass.dashboardWidgets"),
           let decoded = try? JSONDecoder().decode([DashboardWidget].self, from: data),
           !decoded.isEmpty {
            self.dashboardWidgets = Self.normalize(decoded)
        } else {
            self.dashboardWidgets = DashboardWidgetID.allCases.map {
                DashboardWidget(id: $0, visible: true)
            }
        }
    }

    /// Asegura que TODOS los widget IDs estén en el array (agrega los que falten al final).
    private static func normalize(_ arr: [DashboardWidget]) -> [DashboardWidget] {
        var result = arr
        let existing = Set(arr.map { $0.id })
        for id in DashboardWidgetID.allCases where !existing.contains(id) {
            result.append(DashboardWidget(id: id, visible: true))
        }
        return result
    }

    func moveWidget(fromOffsets source: IndexSet, toOffset destination: Int) {
        dashboardWidgets.move(fromOffsets: source, toOffset: destination)
    }

    func toggleWidget(_ id: DashboardWidgetID) {
        if let idx = dashboardWidgets.firstIndex(where: { $0.id == id }) {
            dashboardWidgets[idx].visible.toggle()
        }
    }
}

// MARK: - Tint preset

struct TintPreset: Identifiable, Hashable {
    let name: String
    let hex: UInt32
    var id: String { name }
    var color: Color { Color(hex: hex) }
}

// MARK: - Widget model

enum DashboardWidgetID: String, Codable, CaseIterable, Identifiable {
    case hero, stats, upcoming, weekly, courses

    var id: String { rawValue }
    var label: String {
        switch self {
        case .hero:     return "Saludo"
        case .stats:    return "Estadísticas rápidas"
        case .upcoming: return "Próximas entregas y Hoy"
        case .weekly:   return "Próximos 7 días"
        case .courses:  return "Cursos activos"
        }
    }
    var symbol: String {
        switch self {
        case .hero:     return "sun.max"
        case .stats:    return "chart.bar"
        case .upcoming: return "calendar.badge.clock"
        case .weekly:   return "calendar"
        case .courses:  return "books.vertical"
        }
    }
}

struct DashboardWidget: Codable, Identifiable, Equatable {
    var id: DashboardWidgetID
    var visible: Bool
}

// MARK: - Adaptive surface modifier

extension View {
    /// Superficie de contenido según la preferencia del usuario.
    ///
    /// - `solid`  → opaca. Máxima legibilidad, cero refracción.
    /// - `subtle` → casi opaca con rim especular. El default: deja pasar el
    ///              ambiente lo justo para que la app se sienta viva.
    /// - `glass`  → Liquid Glass real sobre el contenido. Bonito en pantallas
    ///              poco densas, ruidoso en tablas; por eso no es el default.
    @ViewBuilder
    func adaptiveSurface(_ prefs: UserPrefs,
                         cornerRadius: CGFloat = Radius.lg,
                         elevation: Elevation = .low) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch prefs.glass {
        case .solid:
            self
                .background(shape.fill(Palette.surface))
                // Un velo de luz en la mitad de arriba. Es lo que separa el
                // panel de plástico de un rectángulo blanco.
                .background(shape.fill(Palette.specular).opacity(0.5))
                .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
                .clipShape(shape)
                .containerShape(shape)
                .elevation(elevation)
        case .subtle:
            self.contentCard(radius: cornerRadius, elevation: elevation)
        case .glass:
            self.glassBar(radius: cornerRadius)
                .elevation(elevation)
        }
    }
}
