import Foundation
import Security

/// Wrapper mínimo sobre Keychain para guardar strings.
/// Nunca guardamos el PIN — solo tokens de larga vida.
enum Keychain {

    enum Error: Swift.Error, LocalizedError {
        case status(OSStatus)
        case encoding

        var errorDescription: String? {
            switch self {
            case .status(let s): return "Keychain error: \(s)"
            case .encoding:      return "No se pudo codificar el valor a UTF-8."
            }
        }
    }

    /// Apaga el diálogo del llavero mientras dura la operación.
    ///
    /// macOS pregunta la contraseña cuando un binario toca un ítem cuyo ACL
    /// pertenece a OTRO binario. `kSecUseAuthenticationUI` no sirve para
    /// callarlo: esa clave gobierna el llavero de protección de datos, no el
    /// llavero de archivo (`login.keychain`), que es donde viven estos ítems.
    /// Lo único que apaga el diálogo del llavero de archivo es esto, que además
    /// es un interruptor de TODO el proceso — por eso se enciende y se apaga
    /// alrededor de cada llamada y no una vez al arrancar.
    ///
    /// Con la interacción apagada, una operación que habría preguntado falla con
    /// `errSecInteractionNotAllowed`. Eso es exactamente lo que queremos: mejor
    /// re-loguear en silencio que interrumpir con un diálogo del sistema.
    private static func silently<T>(_ body: () -> T) -> T {
        #if os(macOS)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        #endif
        // En iOS no existe este API legado (`SecKeychain*`, del llavero de
        // archivo de macOS): los ítems de la app no disparan un diálogo del
        // sistema, así que no hace falta apagar nada.
        return body()
    }

    static func save(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw Error.encoding }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Se borra y se recrea en vez de usar `SecItemUpdate`. Modificar un ítem
        // exige autorización sobre su ACL; crearlo de cero lo hace nacer con el
        // ACL de la app actual, que es lo que queremos.
        var full = query
        full[kSecValueData as String] = data
        full[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status: OSStatus = silently {
            SecItemDelete(query as CFDictionary)
            return SecItemAdd(full as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Error.status(status) }
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status: OSStatus = silently {
            var local: AnyObject?
            let s = SecItemCopyMatching(query as CFDictionary, &local)
            out = local
            return s
        }
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status: OSStatus = silently { SecItemDelete(query as CFDictionary) }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
