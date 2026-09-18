// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "UAMClass",
    platforms: [
        // macOS 26 es el piso, y no es negociable para el diseño:
        //
        // El sistema decide si una app recibe Liquid Glass mirando el campo `sdk`
        // de LC_BUILD_VERSION en el binario. Si es < 26, macOS la mete en modo de
        // compatibilidad heredado y `glassEffect` se degrada a material opaco.
        // SwiftPM estampa ese campo con el valor del deployment target, así que
        // apuntar a .v15 producía `sdk 15.0` y desactivaba todo el vidrio, aunque
        // el binario se compilara contra el SDK 27.
        //
        // Requiere swift-tools-version 6.2: `.v26` no existe antes.
        .macOS(.v26)
    ],
    products: [
        .executable(name: "UAMClass", targets: ["UAMClass"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "UAMClass",
            path: "Sources/UAMClass",
            // El logotipo de la UAM viaja dentro del binario: se lee con
            // `Bundle.module`, no desde una ruta del disco del usuario.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
