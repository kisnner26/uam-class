import SwiftUI

// MARK: - Marca
//
// El logotipo real de la UAM, embebido en el binario. Reemplaza al castillo
// genérico que venía de la iconografía del sistema.
//
// Se carga por `Bundle.module` y no por una ruta de disco: así viaja con la app
// y no se rompe si el archivo original se mueve o se borra.

enum Brand {
    static let logo: PlatformImage? = load("uam-logo")
    static let mark: PlatformImage? = load("uam-mark")

    private static func load(_ name: String) -> PlatformImage? {
        // `Bundle.module` solo existe cuando SwiftPM genera el accessor (target
        // macOS). El target de Xcode para iOS no es un paquete: ahí las
        // imágenes van sueltas en el bundle principal.
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: name, withExtension: "png") else { return nil }
        return PlatformImage(fileURL: url)
    }
}

/// El logotipo completo "UAM". Para encabezados y pantallas de bienvenida.
struct UAMLogo: View {
    var height: CGFloat = 40

    var body: some View {
        Group {
            if let img = Brand.logo {
                Image(platformImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Respaldo tipográfico si el recurso no cargara.
                Text("UAM")
                    .font(.system(size: height * 0.8, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(height: height)
    }
}

/// La marca cuadrada, para avatares de plataforma y esquinas.
struct UAMMark: View {
    var size: CGFloat = 44
    /// Sobre fondo de color conviene la pastilla blanca; sobre blanco, no.
    var plated: Bool = true

    var body: some View {
        Group {
            if let img = Brand.mark {
                Image(platformImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.13)
            } else {
                Text("U")
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: size, height: size)
        .background {
            if plated {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.10), radius: size * 0.08, y: 1)
            }
        }
    }
}
