import Foundation

/// Orquesta login por plataforma. Cada plataforma es independiente.
actor AuthService {

    struct MoodleOutcome {
        let token: String
        /// Solo para autologin. Puede venir vacío si el sitio no lo entrega.
        let privateToken: String?
        let siteInfo: MoodleSiteInfo
    }

    let moodle: MoodleClient
    let classPortal: ClassPortalClient

    init(moodle: MoodleClient, classPortal: ClassPortalClient) {
        self.moodle = moodle
        self.classPortal = classPortal
    }

    // MARK: - Moodle

    func loginMoodle(cif: String, pin: String) async throws -> MoodleOutcome {
        let token = try await moodle.fetchToken(cif: cif, pin: pin)
        // Se mantiene la clave legacy para compatibilidad con el resume viejo.
        try? Keychain.save(token,
                           service: AppConfig.keychainService,
                           account: AppConfig.keychainMoodleTokenAccount)
        try? Keychain.save(cif,
                           service: AppConfig.keychainService,
                           account: AppConfig.keychainCIFAccount)
        let info = try await moodle.siteInfo()
        return MoodleOutcome(token: token,
                             privateToken: await moodle.currentPrivateToken,
                             siteInfo: info)
    }

    /// Activa una cuenta ya guardada usando su token. Devuelve el perfil si el
    /// token sigue vigente; nil si el server lo rechazó (hay que re-loguear).
    func activate(account: SavedAccount, token: String) async -> MoodleSiteInfo? {
        await moodle.setBaseURL(account.instance.baseURL)
        await moodle.setToken(token)
        // El privado se restaura junto con el token: sin él, "Abrir en Moodle"
        // pierde el autologin al reabrir la app.
        await moodle.setPrivateToken(AccountStore.shared.privateToken(for: account))
        do {
            return try await moodle.siteInfo()
        } catch {
            await moodle.setToken(nil)
            return nil
        }
    }

    func tryResume() async -> MoodleSiteInfo? {
        guard let token = Keychain.read(service: AppConfig.keychainService,
                                        account: AppConfig.keychainMoodleTokenAccount) else {
            return nil
        }
        await moodle.setToken(token)
        do {
            return try await moodle.siteInfo()
        } catch {
            Keychain.delete(service: AppConfig.keychainService,
                            account: AppConfig.keychainMoodleTokenAccount)
            await moodle.setToken(nil)
            return nil
        }
    }

    func logoutMoodle() async {
        Keychain.delete(service: AppConfig.keychainService,
                        account: AppConfig.keychainMoodleTokenAccount)
        await moodle.setToken(nil)
    }

    func lastCIF() -> String? {
        Keychain.read(service: AppConfig.keychainService,
                      account: AppConfig.keychainCIFAccount)
    }

    // MARK: - CLASS Portal

    func loginClassPortal(cif: String, pin: String) async throws -> ClassPortalStatus {
        let result = try await classPortal.login(cif: cif, pin: pin)
        return result.status
    }

    func logoutClassPortal() async {
        // Placeholder: en el futuro, invalidar cookies del jar.
    }
}
