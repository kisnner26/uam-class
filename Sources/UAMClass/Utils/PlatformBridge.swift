import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Puente multiplataforma
//
// UAM Class nació en macOS y usa AppKit en puñados de sitios puntuales (portapapeles,
// abrir URLs, cargar imágenes, colores dinámicos claro/oscuro). Esta capa concentra esos
// puntos de contacto para que el resto del código no le importe si corre en Mac o iPhone.

#if canImport(AppKit)
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #elseif canImport(UIKit)
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    convenience init?(fileURL url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
}

enum PlatformBridge {
    static func copyToClipboard(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }

    static func openURL(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

extension Color {
    /// Componentes sRGB (r, g, b, a), sin acoplar a NSColor/UIColor en el sitio de uso.
    var srgbComponents: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(AppKit)
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        #elseif canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #endif
    }

    /// Color dinámico claro/oscuro sin acoplarse a NSColor/UIColor en el sitio de uso.
    static func dynamicRGB(light: UInt32, lightAlpha: Double = 1,
                            dark: UInt32, darkAlpha: Double = 1) -> Color {
        func components(_ hex: UInt32) -> (Double, Double, Double) {
            (Double((hex >> 16) & 0xFF) / 255.0,
             Double((hex >> 8) & 0xFF) / 255.0,
             Double(hex & 0xFF) / 255.0)
        }
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = components(isDark ? dark : light)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #elseif canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let (r, g, b) = components(isDark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: isDark ? darkAlpha : lightAlpha)
        })
        #endif
    }
}
