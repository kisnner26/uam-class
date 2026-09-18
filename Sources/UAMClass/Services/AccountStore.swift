import Foundation
import SwiftUI
import Combine

// MARK: - Cuenta guardada
//
// Acceso rápido a TUS propias cuentas de UAM Virtual (grado, Language Center,
// posgrado, o varias credenciales tuyas). Cambiás entre ellas sin reescribir el
// PIN.
//
// Cómo funciona, y por qué NO con cookies:
//
// La app no usa cookies — se autentica contra la API de Moodle y recibe un
// token de web service, que es lo que persiste. Ese token es más estable que
// una cookie de navegador (dura semanas, no horas) y es el único que sirve para
// las llamadas de datos. Así que "recordar la sesión" = guardar ese token.
//
// El token vive SIEMPRE en el Keychain, cifrado por el sistema. Lo único que se
// guarda en claro (UserDefaults) es el metadato no sensible para pintar la
// lista: nombre, CIF e instancia. El PIN no se guarda en ningún lado, nunca.

struct SavedAccount: Codable, Identifiable, Equatable {
    /// Estable entre lanzamientos: instancia + CIF. Es también la parte
    /// variable de la clave del token en el Keychain.
    let id: String
    var cif: String
    var instanceRaw: String
    var fullname: String
    var username: String
    var userid: Int
    var lastUsed: Date

    var instance: AppConfig.MoodleInstance {
        AppConfig.MoodleInstance(rawValue: instanceRaw) ?? .grado
    }

    var initials: String { Fmt.initials(fullname) }
    var displayName: String { Fmt.properName(fullname) }

    static func makeID(cif: String, instance: AppConfig.MoodleInstance) -> String {
        "\(instance.rawValue)::\(cif.lowercased())"
    }

    /// Clave del token dentro del Keychain.
    ///
    /// El `v2` no es decorativo. Los ítems que crearon los builds sin firma
    /// quedaron con un ACL que la app firmada ya no puede tocar — ni para
    /// leerlos ni para borrarlos sin que macOS pida la contraseña del llavero.
    /// Cambiar de namespace los deja como basura inofensiva y hace que los
    /// nuevos nazcan con el ACL de la app actual, que es la única forma de que
    /// el diálogo no vuelva.
    var keychainAccount: String { "moodle_token::v2::\(id)" }

    /// El token privado del login. Va aparte porque no sirve para llamar a la
    /// API — su único uso es pedir llaves de autologin.
    var keychainPrivateAccount: String { "moodle_ptoken::v2::\(id)" }
}

// MARK: - Store

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var accounts: [SavedAccount] = []
    /// id de la cuenta activa, o nil si no hay sesión Moodle.
    @Published private(set) var activeID: String?

    private let ud = UserDefaults.standard
    private let indexKey = "UAMClass.accounts.index"
    private let activeKey = "UAMClass.accounts.active"

    private init() {
        load()
    }

    var active: SavedAccount? {
        accounts.first { $0.id == activeID }
    }

    /// Ordenadas por uso reciente, la activa primero.
    var ordered: [SavedAccount] {
        accounts.sorted { a, b in
            if a.id == activeID { return true }
            if b.id == activeID { return false }
            return a.lastUsed > b.lastUsed
        }
    }

    // MARK: Alta / actualización

    /// Registra (o actualiza) una cuenta tras un login exitoso y guarda su token.
    /// Si la cuenta ya existía, refresca el token y los metadatos.
    func upsert(cif: String,
                privateToken: String? = nil,
                instance: AppConfig.MoodleInstance,
                token: String,
                info: MoodleSiteInfo) {
        let id = SavedAccount.makeID(cif: cif, instance: instance)
        let account = SavedAccount(
            id: id,
            cif: cif,
            instanceRaw: instance.rawValue,
            fullname: info.fullname,
            username: info.username,
            userid: info.userid,
            lastUsed: Date()
        )

        // Token al Keychain bajo la clave propia de esta cuenta.
        try? Keychain.save(token,
                           service: AppConfig.keychainService,
                           account: account.keychainAccount)
        if let pt = privateToken, !pt.isEmpty {
            try? Keychain.save(pt,
                               service: AppConfig.keychainService,
                               account: account.keychainPrivateAccount)
        }

        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
        activeID = id
        persist()
    }

    func token(for account: SavedAccount) -> String? {
        Keychain.read(service: AppConfig.keychainService,
                      account: account.keychainAccount)
    }

    func privateToken(for account: SavedAccount) -> String? {
        Keychain.read(service: AppConfig.keychainService,
                      account: account.keychainPrivateAccount)
    }

    func markUsed(_ id: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].lastUsed = Date()
        activeID = id
        persist()
    }

    func setActive(_ id: String?) {
        activeID = id
        persist()
    }

    // MARK: Baja

    /// Olvida una cuenta: borra su token del Keychain y la saca del índice.
    func remove(_ account: SavedAccount) {
        Keychain.delete(service: AppConfig.keychainService,
                        account: account.keychainAccount)
        Keychain.delete(service: AppConfig.keychainService,
                        account: account.keychainPrivateAccount)
        accounts.removeAll { $0.id == account.id }
        if activeID == account.id { activeID = nil }
        persist()
    }

    /// Cierra la sesión activa pero conserva las cuentas guardadas.
    func clearActive() {
        activeID = nil
        persist()
    }

    // MARK: Persistencia

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            ud.set(data, forKey: indexKey)
        }
        ud.set(activeID, forKey: activeKey)
    }

    private func load() {
        if let data = ud.data(forKey: indexKey),
           let decoded = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            accounts = decoded
        }
        activeID = ud.string(forKey: activeKey)
    }

    // MARK: Migración

    /// Rescata el token guardado por la versión anterior (clave única
    /// `moodle_token`) para no obligar a re-loguear al actualizar.
    func migrateLegacyTokenIfNeeded(cif: String,
                                    instance: AppConfig.MoodleInstance,
                                    info: MoodleSiteInfo) {
        let id = SavedAccount.makeID(cif: cif, instance: instance)
        guard !accounts.contains(where: { $0.id == id }) else { return }
        guard let legacy = Keychain.read(service: AppConfig.keychainService,
                                         account: AppConfig.keychainMoodleTokenAccount) else { return }
        upsert(cif: cif, instance: instance, token: legacy, info: info)
    }
}
