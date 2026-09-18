import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
final class AppState: ObservableObject {

    enum Phase: Equatable {
        case bootstrapping
        case picking
        case signingIn(Platform)
        case signedIn(Platform)
    }

    // MARK: Fase
    @Published var phase: Phase = .bootstrapping

    // MARK: Sesión Moodle
    @Published var moodleSiteInfo: MoodleSiteInfo?
    @Published var courses: [MoodleCourse] = []

    // MARK: Sesión CLASS Portal
    @Published var classPortalStatus: ClassPortalStatus?

    // MARK: Errores por plataforma
    @Published var lastError: String?

    // MARK: Modo offline (fallback a cache)
    @Published var isOffline: Bool = false
    @Published var lastSync: Date?

    // MARK: Instancia Moodle seleccionada
    @Published var moodleInstance: AppConfig.MoodleInstance = AppConfig.defaultMoodleInstance

    // MARK: UI overlays
    @Published var showCommandPalette: Bool = false
    @Published var showArchiver: Bool = false
    @Published var showStudyTimer: Bool = false
    /// Set desde el CommandPalette; MainWindow lo consume para pushear a detail.
    @Published var pendingCourseOpen: MoodleCourse?
    /// Sección que otra vista pidió abrir — los mosaicos del menú de Inicio.
    /// `MainWindow` la consume y la limpia.
    @Published var pendingSectionOpen: AppSection?

    /// Intento de examen en curso. Se presenta como overlay a pantalla completa
    /// desde `RootView`, por encima de todo: un examen no puede quedar dentro de
    /// un sheet anidado del que te podés salir sin querer.
    @Published var activeQuiz: ActiveQuiz?

    struct ActiveQuiz: Identifiable, Equatable {
        let quiz: MoodleQuiz
        let attempt: MoodleQuizAttempt
        let course: MoodleCourse?
        let password: String?
        /// true = solo lectura, para revisar un intento ya entregado.
        let review: Bool
        var id: Int { attempt.id }

        static func == (a: ActiveQuiz, b: ActiveQuiz) -> Bool {
            a.attempt.id == b.attempt.id && a.review == b.review
        }
    }

    // MARK: Datos derivados
    @Published var upcomingAssignments: [MoodleAssignment] = []

    // MARK: Filtro de período
    //
    // Global a propósito: el período es un contexto, no un filtro por pantalla.
    // Si estás mirando el corte actual, lo mirás en materias, tareas, notas y
    // exámenes a la vez. `visibleCourses` es la única lista que deben consumir
    // las vistas; `courses` queda como la matrícula completa.

    @Published var periodScope: PeriodScope = .current {
        didSet { UserDefaults.standard.set(scopeKey(periodScope), forKey: Self.scopeDefaultsKey) }
    }

    private static let scopeDefaultsKey = "UAMClass.periodScope"

    /// Cursos que la UI debe mostrar, ya filtrados por el período elegido.
    var visibleCourses: [MoodleCourse] {
        PeriodIndex.filter(courses, scope: periodScope)
    }

    var availablePeriods: [AcademicPeriod] { PeriodIndex.periods(in: courses) }
    var currentPeriod: AcademicPeriod? { PeriodIndex.current(in: courses) }

    /// Cuántos cursos quedan fuera por el filtro. Se muestra para que nadie crea
    /// que le faltan materias.
    var hiddenCourseCount: Int { max(0, courses.count - visibleCourses.count) }

    private func scopeKey(_ s: PeriodScope) -> String {
        switch s {
        case .current:         return "current"
        case .previous:        return "previous"
        case .all:             return "all"
        case .specific(let p): return "p:\(p.year)-\(p.term)"
        }
    }

    func restorePeriodScope() {
        guard let raw = UserDefaults.standard.string(forKey: Self.scopeDefaultsKey) else { return }
        switch raw {
        case "previous": periodScope = .previous
        case "all":      periodScope = .all
        case let s where s.hasPrefix("p:"):
            let parts = s.dropFirst(2).split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 {
                periodScope = .specific(AcademicPeriod(year: parts[0], term: parts[1]))
            }
        default:         periodScope = .current
        }
    }

    // MARK: Servicios
    let moodle = MoodleClient()
    let classPortal = ClassPortalClient()
    /// Cache de esta ventana. La principal usa el compartido; cada ventana de
    /// cuenta secundaria recibe el suyo para no pisar datos de otra cuenta.
    private(set) var cache = OfflineCache.shared
    lazy var auth = AuthService(moodle: moodle, classPortal: classPortal)

    // MARK: - Ciclo de vida

    let accounts = AccountStore.shared

    func bootstrap() async {
        // Registrar el cliente para RemoteImage
        MoodleClientRegistry.shared.client = moodle
        restorePeriodScope()

        if let info = await auth.tryResume() {
            self.moodleSiteInfo = info
            // Traspaso del token legacy al almacén multi-cuenta la primera vez.
            let cif = Keychain.read(service: AppConfig.keychainService,
                                    account: AppConfig.keychainCIFAccount) ?? info.username
            accounts.migrateLegacyTokenIfNeeded(cif: cif,
                                                instance: moodleInstance,
                                                info: info)
            withAnimation(Motion.spring) { self.phase = .signedIn(.moodle) }
            await refreshCourses()
            // Indexado silencioso de archivos locales
            Task.detached(priority: .background) {
                await LocalFileSearch.shared.rebuildIndex()
            }
        } else {
            // Sin sesión — igual intentar mostrar cache si existe
            if let cached = cache.loadCourses(), !cached.isEmpty {
                self.courses = cached
                self.isOffline = true
            }
            withAnimation(Motion.spring) { self.phase = .picking }
        }
    }

    // MARK: - Navegación

    func choosePlatform(_ platform: Platform) {
        self.lastError = nil
        withAnimation(Motion.spring) { self.phase = .signingIn(platform) }
    }

    func backToPicker() {
        self.lastError = nil
        withAnimation(Motion.spring) { self.phase = .picking }
    }

    // MARK: - Login

    func login(cif: String, pin: String, into platform: Platform) async {
        self.lastError = nil
        switch platform {
        case .moodle:
            do {
                await moodle.setBaseURL(moodleInstance.baseURL)
                let outcome = try await auth.loginMoodle(cif: cif, pin: pin)
                self.moodleSiteInfo = outcome.siteInfo
                // Guarda la cuenta para acceso rápido en el futuro.
                accounts.upsert(cif: cif, privateToken: outcome.privateToken,
                                instance: moodleInstance,
                                token: outcome.token, info: outcome.siteInfo)
                withAnimation(Motion.spring) { self.phase = .signedIn(.moodle) }
                await refreshCourses()
            } catch let e as MoodleClient.APIError {
                self.lastError = friendly(e)
            } catch {
                self.lastError = error.localizedDescription
            }

        case .classPortal:
            do {
                let status = try await auth.loginClassPortal(cif: cif, pin: pin)
                self.classPortalStatus = status
                switch status {
                case .ok:
                    withAnimation(Motion.spring) { self.phase = .signedIn(.classPortal) }
                case .portalLocked:
                    self.lastError = "El portal CLASS está cerrado ahora mismo (patrón 0_N_). Volvé cuando termine el periodo de inscripciones."
                case .badCredentials:
                    self.lastError = "CIF o PIN incorrectos."
                case .wrongPortal:
                    self.lastError = "Este portal es solo para estudiantes."
                case .adFailed(let msg):
                    self.lastError = "Validación falló: \(msg)"
                case .unknown(let raw):
                    self.lastError = "Respuesta inesperada del servidor: \(raw)"
                }
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Sesión

    func logout(from platform: Platform) async {
        switch platform {
        case .moodle:
            await auth.logoutMoodle()
            // Olvida la cuenta activa por completo (token incluido). Cerrar
            // sesión es una acción explícita: si solo querés cambiar de cuenta,
            // usá el selector, que conserva las demás.
            if let active = accounts.active {
                accounts.remove(active)
            }
            self.moodleSiteInfo = nil
            self.courses = []
        case .classPortal:
            await auth.logoutClassPortal()
            self.classPortalStatus = nil
        }
        withAnimation(Motion.spring) { self.phase = .picking }
    }

    // MARK: - Cambio de cuenta

    @Published var switchingAccount = false

    /// Cambia a una cuenta ya guardada sin pedir PIN. Si el token venció, manda
    /// al login de esa instancia para renovarlo.
    func switchTo(account: SavedAccount) async {
        guard account.id != accounts.activeID else { return }
        switchingAccount = true
        defer { switchingAccount = false }

        guard let token = accounts.token(for: account) else {
            // Sin token guardado: hay que re-loguear.
            promptRelogin(for: account)
            return
        }

        self.lastError = nil
        // Limpia datos de la cuenta anterior para que no se filtren en la UI ni
        // en el cache offline (las materias de otra cuenta no son las tuyas).
        self.courses = []
        self.upcomingAssignments = []
        cache.clear()

        if let info = await auth.activate(account: account, token: token) {
            self.moodleInstance = account.instance
            self.moodleSiteInfo = info
            accounts.markUsed(account.id)
            // Refresca el token legacy por si el silent-resume lo usa.
            try? Keychain.save(token,
                               service: AppConfig.keychainService,
                               account: AppConfig.keychainMoodleTokenAccount)
            try? Keychain.save(account.cif,
                               service: AppConfig.keychainService,
                               account: AppConfig.keychainCIFAccount)
            withAnimation(Motion.spring) { self.phase = .signedIn(.moodle) }
            await refreshCourses()
            ToastCenter.shared.show("Cuenta: \(account.displayName)",
                                    symbol: "person.crop.circle.badge.checkmark",
                                    tint: UserPrefs.shared.tint)
        } else {
            // Token vencido o revocado.
            promptRelogin(for: account)
        }
    }

    /// Arranca esta instancia directamente en una cuenta guardada.
    ///
    /// Lo usa cada ventana secundaria: cada una tiene su PROPIO `AppState` y su
    /// propio `MoodleClient`, así que dos cuentas pueden estar abiertas a la vez
    /// sin pisarse el token. Nunca toca las claves "legacy" del Keychain ni el
    /// `activeID` global — eso es de la ventana principal.
    func bootstrapWindow(accountID: String) async {
        // Cache propio: sin esto, esta ventana pisaría las materias de la cuenta
        // que esté abierta en la ventana principal.
        cache = OfflineCache(scope: accountID)
        restorePeriodScope()

        guard let account = accounts.accounts.first(where: { $0.id == accountID }),
              let token = accounts.token(for: account) else {
            withAnimation(Motion.spring) { phase = .picking }
            return
        }

        moodleInstance = account.instance
        if let info = await auth.activate(account: account, token: token) {
            moodleSiteInfo = info
            withAnimation(Motion.spring) { phase = .signedIn(.moodle) }
            await refreshCourses()
        } else {
            lastError = "La sesión de \(account.displayName) venció. Ingresá tu PIN de nuevo."
            withAnimation(Motion.spring) { phase = .signingIn(.moodle) }
        }
    }

    /// Lleva al login para agregar otra cuenta (o renovar una vencida).
    func addAccount() {
        self.moodleInstance = AppConfig.defaultMoodleInstance
        self.lastError = nil
        withAnimation(Motion.spring) { self.phase = .signingIn(.moodle) }
    }

    private func promptRelogin(for account: SavedAccount) {
        self.moodleInstance = account.instance
        self.lastError = "La sesión de \(account.displayName) venció. Ingresá tu PIN de nuevo."
        withAnimation(Motion.spring) { self.phase = .signingIn(.moodle) }
    }

    func refreshCourses() async {
        guard let uid = moodleSiteInfo?.userid else { return }
        do {
            let fresh = try await moodle.courses(userId: uid)
            self.courses = fresh
            self.isOffline = false
            self.lastSync = Date()
            cache.saveCourses(fresh)
            await refreshUpcomingAndSchedule()
        } catch {
            // Fallback offline: cargar del cache si existe
            if let cached = cache.loadCourses(), !cached.isEmpty {
                self.courses = cached
                self.isOffline = true
                self.lastError = nil
                await refreshUpcomingAndSchedule()
            } else {
                self.lastError = "No se pudieron cargar los cursos: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers con fallback offline

    /// Contents de un curso con fallback a cache si el server falla.
    func courseContents(courseId: Int) async throws -> [MoodleCourseSection] {
        do {
            let fresh = try await moodle.courseContents(courseId: courseId)
            cache.saveContents(fresh, courseId: courseId)
            return fresh
        } catch {
            if let cached = cache.loadContents(courseId: courseId) {
                self.isOffline = true
                return cached
            }
            throw error
        }
    }

    /// Grades de un curso con fallback a cache.
    func courseGrades(courseId: Int, userId: Int) async throws -> MoodleGradesResponse {
        do {
            let fresh = try await moodle.gradeItems(courseId: courseId, userId: userId)
            cache.saveGrades(fresh, courseId: courseId)
            return fresh
        } catch {
            if let cached = cache.loadGrades(courseId: courseId) {
                self.isOffline = true
                return cached
            }
            throw error
        }
    }

    /// Assignments con fallback a cache.
    func courseAssignments(courseIds: [Int]) async throws -> MoodleAssignmentsResponse {
        let key = courseIds.sorted().map(String.init).joined(separator: "-")
        do {
            let fresh = try await moodle.assignments(courseIds: courseIds)
            cache.saveAssignments(fresh, key: key)
            return fresh
        } catch {
            if let cached = cache.loadAssignments(key: key) {
                self.isOffline = true
                return cached
            }
            throw error
        }
    }

    /// Trae asignaciones, filtra las futuras, programa notificaciones y actualiza el menu bar.
    func refreshUpcomingAndSchedule() async {
        guard !courses.isEmpty else { return }
        do {
            let resp = try await courseAssignments(courseIds: courses.map(\.id))
            var flat: [MoodleAssignment] = []
            var assignToCourse: [Int: MoodleCourse] = [:]
            for group in resp.courses {
                let course = courses.first { $0.id == group.id }
                for a in group.assignments {
                    if let d = a.dueDateOrNil, d > Date() {
                        flat.append(a)
                        if let c = course { assignToCourse[a.id] = c }
                    }
                }
            }
            flat.sort { ($0.dueDateOrNil ?? .distantFuture) < ($1.dueDateOrNil ?? .distantFuture) }
            self.upcomingAssignments = flat

            // Notificaciones locales
            var coursesById: [Int: MoodleCourse] = [:]
            for c in courses { coursesById[c.id] = c }
            await NotificationScheduler.schedule(assignments: flat, coursesById: coursesById)

            // Menu bar (solo macOS)
            #if os(macOS)
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.menuBar?.update(upcoming: flat, coursesById: assignToCourse)
            }
            #endif
        } catch {
            // silencioso
        }
    }

    // MARK: - Helpers

    private func friendly(_ e: MoodleClient.APIError) -> String {
        switch e.errorcode {
        case "invalidlogin", "invalid_login": return "CIF o PIN incorrectos."
        case "usernotconfirmed":              return "Tu usuario Moodle aún no está confirmado."
        case "sitemaintenance":               return "Moodle está en mantenimiento."
        default:                              return e.message
        }
    }
}
