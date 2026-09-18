import Foundation
import Combine

/// Persistencia local (UserDefaults) para preferencias del usuario:
/// favoritos, notas personales, tiempo estudiado, bookmarks.
@MainActor
final class LocalStore: ObservableObject {
    static let shared = LocalStore()

    private let defaults = UserDefaults.standard

    // MARK: Favoritos

    @Published var favoriteCourseIds: Set<Int> = []
    private let favKey = "UAMClass.favorites"

    // MARK: Notas personales por curso (markdown)

    @Published private var notesById: [Int: String] = [:]
    private let notesKey = "UAMClass.notes"

    // MARK: Tiempo estudiado (segundos) por curso

    @Published var studyTimeSeconds: [Int: TimeInterval] = [:]
    private let timeKey = "UAMClass.studytime"

    // MARK: Sesiones (log)

    @Published var studySessions: [StudySession] = []
    private let sessionsKey = "UAMClass.sessions"

    // MARK: Bookmarks de módulos (por curso)

    @Published private var bookmarkedModules: Set<Int> = []
    private let bookmarksKey = "UAMClass.bookmarks"

    // MARK: Tags custom por curso

    @Published private var tagsByCourse: [Int: [String]] = [:]
    private let tagsKey = "UAMClass.tags"

    // MARK: Rating de dificultad por curso (1-5)

    @Published private var ratings: [Int: Int] = [:]
    private let ratingsKey = "UAMClass.ratings"

    // MARK: Cursos recientes (últimos 10 abiertos)

    @Published var recentCourseIds: [Int] = []
    private let recentsKey = "UAMClass.recents"

    /// Asistencia propia, registrada a mano. Independiente de Moodle: funciona
    /// aunque el sitio no tenga el plugin de asistencia instalado.
    @Published private(set) var attendance: [AttendanceRecord] = []
    private let attendanceKey = "UAMClass.attendance"

    /// Horario de clases, escrito a mano. Ver `ScheduleModels`.
    @Published private(set) var schedule: [ClassSlot] = []
    private let scheduleKey = "UAMClass.schedule"

    /// Reglas del piloto automático de tareas. Ver `AutomationModels`.
    @Published private(set) var rules: [AutomationRule] = []
    private let rulesKey = "UAMClass.rules"

    /// Mii por cuenta (clave = `SavedAccount.id`). Es local y no toca Moodle:
    /// tu foto de perfil real sigue siendo la del sitio, esta es tuya y de esta
    /// Mac.
    @Published private(set) var miis: [String: Mii] = [:]
    private let miisKey = "UAMClass.miis"

    init() { load() }

    // MARK: Favoritos API

    func isFavorite(_ courseId: Int) -> Bool { favoriteCourseIds.contains(courseId) }

    func toggleFavorite(_ courseId: Int) {
        if favoriteCourseIds.contains(courseId) {
            favoriteCourseIds.remove(courseId)
        } else {
            favoriteCourseIds.insert(courseId)
        }
        persistFavorites()
    }

    // MARK: Notas API

    func note(for courseId: Int) -> String {
        notesById[courseId] ?? ""
    }
    func setNote(_ text: String, for courseId: Int) {
        notesById[courseId] = text
        persistNotes()
    }

    // MARK: Bookmarks API

    func isBookmarked(_ moduleId: Int) -> Bool { bookmarkedModules.contains(moduleId) }
    func toggleBookmark(_ moduleId: Int) {
        if bookmarkedModules.contains(moduleId) { bookmarkedModules.remove(moduleId) }
        else { bookmarkedModules.insert(moduleId) }
        persistBookmarks()
    }
    var bookmarkedIds: Set<Int> { bookmarkedModules }

    // MARK: Tags API

    func tags(for courseId: Int) -> [String] { tagsByCourse[courseId] ?? [] }
    func setTags(_ tags: [String], for courseId: Int) {
        tagsByCourse[courseId] = tags
        persistTags()
    }
    func addTag(_ tag: String, to courseId: Int) {
        var current = tags(for: courseId)
        let clean = tag.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !current.contains(clean) else { return }
        current.append(clean)
        setTags(current, for: courseId)
    }
    func removeTag(_ tag: String, from courseId: Int) {
        var current = tags(for: courseId)
        current.removeAll { $0 == tag }
        setTags(current, for: courseId)
    }

    // MARK: Rating API

    func rating(for courseId: Int) -> Int { ratings[courseId] ?? 0 }
    func setRating(_ value: Int, for courseId: Int) {
        ratings[courseId] = value
        persistRatings()
    }

    // MARK: Asistencia API

    /// Marca (o cambia) la asistencia de un día para un curso. Un solo registro
    /// por curso y día: volver a marcar el mismo día actualiza, no duplica.
    func markAttendance(courseId: Int, date: Date, status: AttendanceStatus, note: String? = nil) {
        let day = Calendar.current.startOfDay(for: date)
        attendance.removeAll { $0.courseId == courseId && $0.day == day }
        attendance.append(AttendanceRecord(courseId: courseId, day: day,
                                           status: status, note: note))
        persistAttendance()
    }

    func clearAttendance(courseId: Int, date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        attendance.removeAll { $0.courseId == courseId && $0.day == day }
        persistAttendance()
    }

    func attendance(courseId: Int, date: Date) -> AttendanceRecord? {
        let day = Calendar.current.startOfDay(for: date)
        return attendance.first { $0.courseId == courseId && $0.day == day }
    }

    func attendance(courseId: Int) -> [AttendanceRecord] {
        attendance.filter { $0.courseId == courseId }.sorted { $0.day > $1.day }
    }

    /// Porcentaje de presencia (presente + tarde) sobre lo registrado.
    func attendanceRate(courseId: Int) -> Double? {
        let records = attendance(courseId: courseId)
        guard !records.isEmpty else { return nil }
        let present = records.filter { $0.status.countsAsPresent }.count
        return Double(present) / Double(records.count)
    }

    // MARK: Piloto automático API

    func rules(for assignmentID: Int) -> [AutomationRule] {
        rules.filter { $0.assignmentID == assignmentID && !$0.done }
    }

    var pendingRules: [AutomationRule] { rules.filter { !$0.done } }

    func addRule(_ rule: AutomationRule) {
        // Una sola regla viva por tarea: dos reglas sobre la misma entrega se
        // pisarían entre sí y el resultado dependería del orden.
        rules.removeAll { $0.assignmentID == rule.assignmentID && !$0.done }
        rules.append(rule)
        persistRules()
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        persistRules()
    }

    func completeRule(_ id: UUID, outcome: String) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].done = true
        rules[i].outcome = outcome
        persistRules()
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: rulesKey)
        }
    }

    // MARK: Mii API

    func mii(for accountID: String?) -> Mii? {
        guard let id = accountID else { return nil }
        return miis[id]
    }

    func setMii(_ mii: Mii?, for accountID: String) {
        if let mii { miis[accountID] = mii } else { miis.removeValue(forKey: accountID) }
        if let data = try? JSONEncoder().encode(miis) {
            defaults.set(data, forKey: miisKey)
        }
    }

    // MARK: Horario API

    /// Bloques de un día, en orden de reloj.
    func slots(on day: Weekday) -> [ClassSlot] {
        schedule.filter { $0.weekday == day }
                .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Los días que tienen algo, en orden de semana. Un horario vacío no dibuja
    /// siete encabezados vacíos.
    var scheduledDays: [Weekday] {
        Weekday.week.filter { day in schedule.contains { $0.weekday == day } }
    }

    /// Bloques que se pisan con otro. Se calcula una vez y la vista consulta.
    var conflictingSlotIDs: Set<UUID> {
        var out: Set<UUID> = []
        for a in schedule where schedule.contains(where: { a.overlaps($0) }) {
            out.insert(a.id)
        }
        return out
    }

    func upsertSlot(_ slot: ClassSlot) {
        if let i = schedule.firstIndex(where: { $0.id == slot.id }) {
            schedule[i] = slot
        } else {
            schedule.append(slot)
        }
        persistSchedule()
    }

    func removeSlot(_ id: UUID) {
        schedule.removeAll { $0.id == id }
        persistSchedule()
    }

    private func persistSchedule() {
        if let data = try? JSONEncoder().encode(schedule) {
            defaults.set(data, forKey: scheduleKey)
        }
    }

    private func persistAttendance() {
        if let data = try? JSONEncoder().encode(attendance) {
            defaults.set(data, forKey: attendanceKey)
        }
    }

    // MARK: Recientes API

    func trackVisit(_ courseId: Int) {
        recentCourseIds.removeAll { $0 == courseId }
        recentCourseIds.insert(courseId, at: 0)
        if recentCourseIds.count > 10 {
            recentCourseIds = Array(recentCourseIds.prefix(10))
        }
        persistRecents()
    }

    // MARK: Study time API

    func addStudy(seconds: TimeInterval, to courseId: Int) {
        studyTimeSeconds[courseId, default: 0] += seconds
        persistStudyTime()
    }
    func totalStudyThisWeek() -> TimeInterval {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        return studySessions
            .filter { $0.start >= weekAgo }
            .reduce(0) { $0 + $1.duration }
    }

    func logSession(courseId: Int, start: Date, duration: TimeInterval) {
        let s = StudySession(courseId: courseId, start: start, duration: duration)
        studySessions.append(s)
        // Cap: solo 500 más recientes
        if studySessions.count > 500 { studySessions.removeFirst(studySessions.count - 500) }
        persistSessions()
        addStudy(seconds: duration, to: courseId)
    }

    // MARK: Persistence

    private func load() {
        if let arr = defaults.array(forKey: favKey) as? [Int] {
            favoriteCourseIds = Set(arr)
        }
        if let data = defaults.data(forKey: notesKey),
           let dict = try? JSONDecoder().decode([Int: String].self, from: data) {
            notesById = dict
        }
        if let data = defaults.data(forKey: timeKey),
           let dict = try? JSONDecoder().decode([Int: TimeInterval].self, from: data) {
            studyTimeSeconds = dict
        }
        if let data = defaults.data(forKey: sessionsKey),
           let arr = try? JSONDecoder().decode([StudySession].self, from: data) {
            studySessions = arr
        }
        if let arr = defaults.array(forKey: bookmarksKey) as? [Int] {
            bookmarkedModules = Set(arr)
        }
        if let data = defaults.data(forKey: tagsKey),
           let dict = try? JSONDecoder().decode([Int: [String]].self, from: data) {
            tagsByCourse = dict
        }
        if let data = defaults.data(forKey: attendanceKey),
           let decoded = try? JSONDecoder().decode([AttendanceRecord].self, from: data) {
            attendance = decoded
        }
        if let data = defaults.data(forKey: ratingsKey),
           let dict = try? JSONDecoder().decode([Int: Int].self, from: data) {
            ratings = dict
        }
        if let arr = defaults.array(forKey: recentsKey) as? [Int] {
            recentCourseIds = arr
        }
        if let data = defaults.data(forKey: scheduleKey),
           let decoded = try? JSONDecoder().decode([ClassSlot].self, from: data) {
            schedule = decoded
        }
        if let data = defaults.data(forKey: miisKey),
           let decoded = try? JSONDecoder().decode([String: Mii].self, from: data) {
            miis = decoded
        }
        if let data = defaults.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([AutomationRule].self, from: data) {
            rules = decoded
        }
    }

    private func persistFavorites() {
        defaults.set(Array(favoriteCourseIds), forKey: favKey)
    }
    private func persistNotes() {
        if let data = try? JSONEncoder().encode(notesById) {
            defaults.set(data, forKey: notesKey)
        }
    }
    private func persistStudyTime() {
        if let data = try? JSONEncoder().encode(studyTimeSeconds) {
            defaults.set(data, forKey: timeKey)
        }
    }
    private func persistSessions() {
        if let data = try? JSONEncoder().encode(studySessions) {
            defaults.set(data, forKey: sessionsKey)
        }
    }
    private func persistBookmarks() {
        defaults.set(Array(bookmarkedModules), forKey: bookmarksKey)
    }
    private func persistTags() {
        if let data = try? JSONEncoder().encode(tagsByCourse) {
            defaults.set(data, forKey: tagsKey)
        }
    }
    private func persistRatings() {
        if let data = try? JSONEncoder().encode(ratings) {
            defaults.set(data, forKey: ratingsKey)
        }
    }
    private func persistRecents() {
        defaults.set(recentCourseIds, forKey: recentsKey)
    }
}

struct StudySession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let courseId: Int
    let start: Date
    let duration: TimeInterval
}
