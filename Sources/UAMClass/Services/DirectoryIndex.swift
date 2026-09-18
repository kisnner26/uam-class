import Foundation
import SwiftUI

// MARK: - Índice de personas
//
// Por qué existe: la búsqueda remota de Moodle es poco fiable para esto.
// `core_message_search_users` solo devuelve gente a la que PODÉS escribirle
// (depende de la config de mensajería del sitio) y NO indexa el username, así
// que un CIF nunca aparece. `core_user_get_users_by_field` exige coincidencia
// exacta y suele estar restringido.
//
// En cambio `core_enrol_get_enrolled_users` SÍ funciona con este token — es la
// que ya usa la pestaña Personas de cada materia. Así que el índice se arma con
// los participantes de tus cursos: se busca al instante, sin red, y encuentra
// por nombre o CIF.
//
// Ese índice cubre a la gente con la que compartís materias. Para el resto está
// `remoteSearch`, que combina las tres vías remotas que el sitio pueda tener
// abiertas (CIF exacto, búsqueda de mensajería por nombre, y consulta al padrón)
// y devuelve lo que sobreviva, sin exigir cursos en común.

@MainActor
final class DirectoryIndex: ObservableObject {

    struct Entry: Identifiable, Hashable {
        let user: MoodleEnrolledUser
        /// true = vino de la búsqueda remota por CIF, no de tus materias. No
        /// tiene cursos en común y su ficha traerá menos datos.
        var remote: Bool = false
        /// Cursos donde coincidís con esta persona, con su rol en cada uno.
        var courses: [Shared]
        var id: Int { user.id }

        struct Shared: Hashable, Identifiable {
            let course: MoodleCourse
            let role: String
            var id: Int { course.id }
        }

        /// Construye una entrada desde un resultado remoto (sin cursos en común).
        static func remoteResult(_ u: MoodleDirectoryUser) -> Entry {
            Entry(user: MoodleEnrolledUser(
                    id: u.id, fullname: u.fullname, firstname: nil, lastname: nil,
                    email: u.email, profileimageurl: u.profileimageurl,
                    profileimageurlsmall: u.profileimageurlsmall, roles: nil,
                    city: nil, country: nil, username: u.username, idnumber: nil,
                    department: u.department, institution: nil,
                    lastaccess: u.lastaccess, groups: nil),
                  remote: true,
                  courses: [])
        }

        /// Solo sabemos id y nombre (el sitio no dejó leer la ficha). Igual sirve:
        /// con el id se abre el perfil y se le puede escribir.
        static func placeholder(id: Int, name: String) -> Entry {
            Entry(user: MoodleEnrolledUser(
                    id: id, fullname: name, firstname: nil, lastname: nil,
                    email: nil, profileimageurl: nil, profileimageurlsmall: nil,
                    roles: nil, city: nil, country: nil, username: nil,
                    idnumber: nil, department: nil, institution: nil,
                    lastaccess: nil, groups: nil),
                  remote: true,
                  courses: [])
        }

        var isTeacherSomewhere: Bool {
            courses.contains { $0.role.lowercased().contains("docente")
                            || $0.role.lowercased().contains("teacher")
                            || $0.role.lowercased().contains("profesor") }
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var building = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var builtAt: Date?
    /// Cuántos cursos aportaron identidad (CIF). Si es 0, el sitio la oculta.
    @Published private(set) var identityVisible = false

    /// Gente de TODA la universidad, sin importar carrera ni cursos, sacada del
    /// bloque "Usuarios en línea" del sitio (ver `loadSiteWide`).
    @Published private(set) var siteWide: [Entry] = []
    @Published private(set) var siteWideNote: String?
    @Published private(set) var loadingSiteWide = false

    private var indexedCourseIDs: Set<Int> = []
    /// El padrón (`core_user_get_users`) casi siempre está cerrado para cuentas
    /// de estudiante. Si lo rechaza una vez, no se vuelve a intentar en toda la
    /// sesión: gastaría una petición por tecleo para nada.
    private var rosterQueryDenied = false

    // MARK: Construcción

    /// Recorre los cursos y arma el índice. Es idempotente: si ya se indexaron
    /// esos cursos, no vuelve a pedir nada salvo que se fuerce.
    func build(courses: [MoodleCourse], moodle: MoodleClient, force: Bool = false) async {
        let ids = Set(courses.map(\.id))
        if !force, ids == indexedCourseIDs, !entries.isEmpty { return }
        guard !building else { return }

        building = true
        lastError = nil
        progress = 0
        defer { building = false }

        var byUser: [Int: Entry] = [:]
        var failures: [String] = []
        var sawIdentity = false

        for (i, course) in courses.enumerated() {
            do {
                let people = try await moodle.enrolledUsers(courseId: course.id)
                for p in people {
                    if p.cif != nil { sawIdentity = true }
                    let shared = Entry.Shared(course: course, role: p.primaryRole)
                    if var existing = byUser[p.id] {
                        existing.courses.append(shared)
                        // Nos quedamos con el registro más completo.
                        if existing.user.cif == nil && p.cif != nil {
                            existing = Entry(user: p, courses: existing.courses)
                        }
                        byUser[p.id] = existing
                    } else {
                        byUser[p.id] = Entry(user: p, courses: [shared])
                    }
                }
            } catch {
                let name = CourseInfo(course: course).code
                failures.append(name)
            }
            progress = Double(i + 1) / Double(max(1, courses.count))
        }

        entries = byUser.values.sorted { $0.user.fullname < $1.user.fullname }
        indexedCourseIDs = ids
        builtAt = Date()
        identityVisible = sawIdentity

        if entries.isEmpty && !failures.isEmpty {
            lastError = "Moodle rechazó la lista de participantes en \(failures.count) materia\(failures.count == 1 ? "" : "s") (\(failures.prefix(3).joined(separator: ", "))). Puede ser una restricción de privacidad del sitio."
        } else if !failures.isEmpty {
            lastError = "No se pudo leer la lista de \(failures.count) materia\(failures.count == 1 ? "" : "s"): \(failures.prefix(3).joined(separator: ", "))."
        }
    }

    // MARK: Búsqueda

    /// Busca por nombre o CIF. Insensible a mayúsculas y a acentos — "alondra"
    /// tiene que encontrar a "Alondra Sofía".
    func search(_ raw: String) -> [Entry] {
        Self.filter(entries, by: raw)
    }

    /// La misma búsqueda, pero sobre la gente de todo el sitio. Instantánea
    /// también: ya está en memoria, no vuelve a pegarle a la red.
    func searchSiteWide(_ raw: String) -> [Entry] {
        Self.filter(siteWide, by: raw)
    }

    private static func filter(_ pool: [Entry], by raw: String) -> [Entry] {
        let q = fold(raw)
        guard !q.isEmpty else { return [] }

        let terms = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }

        return pool.filter { entry in
            let name = fold(entry.user.fullname)
            let cif  = fold(entry.user.cif ?? "")
            let mail = fold(entry.user.email ?? "")

            // Todos los términos tienen que aparecer en algún lado: así
            // "obando soza" encuentra aunque el orden no coincida.
            return terms.allSatisfy { t in
                name.contains(t) || cif.contains(t) || mail.contains(t)
            }
        }
        .sorted { a, b in
            // Primero quien empieza con lo que escribiste.
            let an = fold(a.user.fullname).hasPrefix(q)
            let bn = fold(b.user.fullname).hasPrefix(q)
            if an != bn { return an }
            return a.user.fullname < b.user.fullname
        }
    }

    // MARK: Búsqueda remota (gente sin cursos en común)

    struct RemoteOutcome {
        var entries: [Entry] = []
        /// Qué falló, si es que algo falló. Se muestra para poder distinguir
        /// "no existe" de "el sitio no me deja preguntar".
        var note: String?
    }

    /// Busca en todo UAM Virtual, no solo en tus materias.
    ///
    /// Se intentan tres vías, porque ninguna sola alcanza y cuál está habilitada
    /// depende de la configuración del sitio:
    ///
    ///  1. `core_user_get_users_by_field` por `username`/`idnumber` — CIF exacto.
    ///  2. `core_message_search_users` — por nombre, parcial. Devuelve contactos
    ///     y no contactos; los no contactos incluyen a gente ajena a tus cursos
    ///     si el sitio permite mensajear a todo el mundo. Solo trae nombre y
    ///     avatar, así que después se enriquece por id para recuperar el CIF.
    ///  3. `core_user_get_users` con comodines — el padrón completo. Es la única
    ///     que encuentra por nombre a cualquiera sin condiciones, y también la
    ///     que más se restringe; por eso va última y solo si no hubo nada.
    func remoteSearch(_ raw: String, moodle: MoodleClient,
                      currentUserId: Int?) async -> RemoteOutcome {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return RemoteOutcome() }

        var found: [Int: MoodleDirectoryUser] = [:]
        var notes: [String] = []

        // 1 · CIF exacto.
        if Self.looksLikeCIF(q) {
            for (field, value) in [("username", q.lowercased()), ("idnumber", q)] {
                if !found.isEmpty { break }
                if let hits = try? await moodle.usersByField(field, values: [value]) {
                    for u in hits { found[u.id] = u }
                }
            }
        }

        // 2 · Nombre, vía mensajería.
        if let uid = currentUserId {
            do {
                let r = try await moodle.searchUsers(currentUserId: uid, search: q, limit: 30)
                let hits = r.contacts + r.noncontacts
                let missing = hits.map(\.id).filter { found[$0] == nil }
                var detailed: [Int: MoodleDirectoryUser] = [:]
                if !missing.isEmpty,
                   let full = try? await moodle.usersByField("id",
                                                            values: missing.map(String.init)) {
                    detailed = Dictionary(full.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                }
                for h in hits where found[h.id] == nil {
                    // Si el sitio no deja leer la ficha, al menos queda el nombre.
                    found[h.id] = detailed[h.id] ?? MoodleDirectoryUser(fromSearch: h)
                }
            } catch {
                notes.append((error as? MoodleClient.APIError)?.message
                             ?? error.localizedDescription)
            }
        }

        // 3 · Padrón completo, solo si lo anterior no dio nada.
        if found.isEmpty, !rosterQueryDenied {
            let terms = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            // Los criterios se combinan con AND, así que un solo término hay que
            // probarlo por separado contra nombre y apellido.
            let attempts: [[(key: String, value: String)]]
            if Self.looksLikeCIF(q) {
                // Acá sí sirve para un CIF a medias: por campo era exacto o nada.
                attempts = [[("username", "%\(q.lowercased())%")]]
            } else if terms.count >= 2 {
                attempts = [[("firstname", "%\(terms[0])%"),
                             ("lastname",  "%\(terms[terms.count - 1])%")]]
            } else {
                attempts = [[("lastname", "%\(q)%")], [("firstname", "%\(q)%")]]
            }
            for criteria in attempts {
                do {
                    for u in try await moodle.usersMatching(criteria) { found[u.id] = u }
                } catch {
                    if error is MoodleClient.APIError { rosterQueryDenied = true }
                    break
                }
            }
        }

        let entries = found.values
            .map(Entry.remoteResult)
            .sorted { $0.user.fullname < $1.user.fullname }

        return RemoteOutcome(entries: entries,
                             note: entries.isEmpty ? notes.first : nil)
    }

    // MARK: Padrón de todo el sitio

    /// Trae gente de TODA la universidad, sin importar carrera ni cursos.
    ///
    /// El bloque "Usuarios en línea" del sitio lista a cualquiera que esté
    /// conectado, sin filtrar por matrícula — es la única vista de Moodle que le
    /// muestra a un estudiante a gente completamente ajena a sus materias. No es
    /// un buscador, pero cada pasada suma personas nuevas al padrón, y una vez
    /// que tenemos su id se les puede pedir la ficha completa como a cualquiera.
    ///
    /// Por eso el resultado se ACUMULA entre llamadas en vez de reemplazarse:
    /// llamándolo cada tanto, el directorio crece solo.
    func loadSiteWide(moodle: MoodleClient, currentUserId: Int?) async {
        guard !loadingSiteWide else { return }
        loadingSiteWide = true
        defer { loadingSiteWide = false }

        var html: [String] = []
        var problem: String?

        do {
            html += try await moodle.siteBlocks().compactMap { $0.contents?.content }
        } catch {
            problem = (error as? MoodleClient.APIError)?.message ?? error.localizedDescription
        }
        // El bloque puede estar en el Área personal y no en la portada.
        if let uid = currentUserId,
           let blocks = try? await moodle.dashboardBlocks(userId: uid) {
            html += blocks.compactMap { $0.contents?.content }
        }

        var names: [Int: String] = [:]
        for chunk in html {
            for hit in Self.profileLinks(in: chunk) where hit.id != currentUserId {
                names[hit.id] = hit.name
            }
        }

        let known = Set(entries.map(\.user.id)).union(siteWide.map(\.user.id))
        let fresh = names.keys.filter { !known.contains($0) }
        guard !fresh.isEmpty else {
            siteWideNote = html.isEmpty ? (problem ?? "El sitio no expone sus bloques.") : nil
            return
        }

        // Con el id ya se puede pedir la ficha: `..._by_field` por `id` no exige
        // compartir nada. Si el sitio lo niega, queda al menos el nombre.
        var built: [Entry] = []
        for group in stride(from: 0, to: fresh.count, by: 50).map({
            Array(fresh[$0..<min($0 + 50, fresh.count)])
        }) {
            if let full = try? await moodle.usersByField("id", values: group.map(String.init)) {
                built += full.map(Entry.remoteResult)
                let got = Set(full.map(\.id))
                built += group.filter { !got.contains($0) }
                              .compactMap { id in names[id].map { Entry.placeholder(id: id, name: $0) } }
            } else {
                built += group.compactMap { id in names[id].map { Entry.placeholder(id: id, name: $0) } }
            }
        }

        siteWide = (siteWide + built).sorted { $0.user.fullname < $1.user.fullname }
        siteWideNote = nil
    }

    /// Saca los enlaces a perfiles del HTML de un bloque. El markup depende del
    /// tema del sitio, así que se busca lo único que no cambia: el href.
    static func profileLinks(in html: String) -> [(id: Int, name: String)] {
        let pattern = #"<a[^>]+href="[^"]*/user/(?:view|profile)\.php\?id=(\d+)[^"]*"[^>]*>([\s\S]*?)</a>"#
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        var out: [(Int, String)] = []
        for m in rx.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges >= 3,
                  let id = Int(ns.substring(with: m.range(at: 1))) else { continue }
            let name = HTMLClean.plain(ns.substring(with: m.range(at: 2)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Los avatares generan un segundo enlace sin texto al mismo perfil.
            guard !name.isEmpty else { continue }
            out.append((id, name))
        }
        return out
    }

    /// ¿Parece un CIF y no un nombre? Sin espacios, con algún dígito y corto.
    /// Los CIF de UAM son numéricos, pero se acepta alfanumérico por si acaso.
    static func looksLikeCIF(_ q: String) -> Bool {
        guard q.count >= 4, q.count <= 20, !q.contains(" ") else { return false }
        return q.contains(where: \.isNumber)
            && q.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    func entry(for userID: Int) -> Entry? {
        entries.first { $0.user.id == userID }
    }

    /// Normaliza para comparar: sin acentos, sin mayúsculas, sin espacios extra.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
