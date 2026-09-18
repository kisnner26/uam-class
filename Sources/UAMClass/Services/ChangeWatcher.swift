import Foundation
import SwiftUI

/// Compara cada materia contra la última foto guardada y reporta qué cambió.
///
/// La regla que gobierna todo: **la primera vez no reporta nada**. Sin foto
/// previa, todo parecería nuevo y el diario nacería con doscientas entradas
/// inútiles. La primera pasada solo establece la línea de base.
@MainActor
final class ChangeWatcher: ObservableObject {
    static let shared = ChangeWatcher()

    @Published private(set) var changes: [CourseChange] = []
    @Published private(set) var scanning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastScan: Date?
    @Published private(set) var baselineOnly = false

    private let defaults = UserDefaults.standard
    private let changesKey   = "UAMClass.changes"
    private let snapshotsKey = "UAMClass.snapshots"
    private let lastScanKey  = "UAMClass.changes.lastScan"

    private var snapshots: [Int: CourseSnapshot] = [:]

    var unseenCount: Int { changes.filter { !$0.seen }.count }

    private init() { load() }

    // MARK: Escaneo

    func scan(courses: [MoodleCourse], moodle: MoodleClient) async {
        guard !scanning, !courses.isEmpty else { return }
        scanning = true
        progress = 0
        defer { scanning = false }

        var found: [CourseChange] = []
        var firstTime = true

        for (i, course) in courses.enumerated() {
            defer { progress = Double(i + 1) / Double(courses.count) }

            let fresh = await snapshot(of: course, moodle: moodle)
            guard let fresh else { continue }

            if let old = snapshots[course.id], old.takenAt != .distantPast {
                firstTime = false
                found += diff(old: old, new: fresh, course: course)
            }
            snapshots[course.id] = fresh
        }

        // Las novedades van arriba, y lo crítico arriba de todo dentro del día.
        changes = (found + changes)
            .sorted { a, b in
                if a.detectedAt != b.detectedAt { return a.detectedAt > b.detectedAt }
                return a.kind.isCritical && !b.kind.isCritical
            }
        // El diario no crece para siempre.
        if changes.count > 300 { changes = Array(changes.prefix(300)) }

        baselineOnly = firstTime && found.isEmpty
        lastScan = Date()
        persist()
    }

    private func snapshot(of course: MoodleCourse, moodle: MoodleClient) async -> CourseSnapshot? {
        var assignments: [Int: AssignmentFingerprint] = [:]
        var modules: [Int: ModuleFingerprint] = [:]

        if let resp = try? await moodle.assignments(courseIds: [course.id]) {
            for a in resp.courses.flatMap(\.assignments) {
                assignments[a.id] = AssignmentFingerprint(
                    name: HTMLClean.plain(a.name),
                    duedate: a.duedate,
                    cutoffdate: a.cutoffdate,
                    introHash: StableHash.of(HTMLClean.plain(a.intro)))
            }
        }

        if let sections = try? await moodle.courseContents(courseId: course.id) {
            for m in sections.flatMap(\.modules) {
                modules[m.id] = ModuleFingerprint(
                    name: m.displayName,
                    fileNames: (m.contents ?? []).compactMap(\.filename).sorted())
            }
        }

        // Si las dos llamadas fallaron, no hay foto: devolver una vacía borraría
        // la anterior y el próximo escaneo reportaría todo como nuevo.
        guard !assignments.isEmpty || !modules.isEmpty else { return nil }

        return CourseSnapshot(takenAt: Date(), assignments: assignments, modules: modules)
    }

    // MARK: Comparación

    private func diff(old: CourseSnapshot, new: CourseSnapshot,
                      course: MoodleCourse) -> [CourseChange] {
        let code = CourseInfo(course: course).code
        var out: [CourseChange] = []

        func add(_ kind: CourseChange.Kind, _ subject: String, _ detail: String) {
            out.append(CourseChange(
                id: "\(course.id)-\(kind.rawValue)-\(subject)-\(Date().timeIntervalSince1970)",
                courseId: course.id, courseCode: code, kind: kind,
                subject: subject, detail: detail,
                detectedAt: Date(), seen: false))
        }

        // Tareas
        for (id, now) in new.assignments {
            guard let before = old.assignments[id] else {
                add(.assignmentAdded, now.name, "Apareció en la materia.")
                continue
            }

            if before.duedate != now.duedate {
                add(.dueDateMoved, now.name, dueDateText(from: before.duedate, to: now.duedate))
            }
            if before.name != now.name {
                add(.assignmentRenamed, now.name, "Antes se llamaba “\(before.name)”.")
            }
            if before.introHash != now.introHash && before.name == now.name {
                add(.assignmentEdited, now.name,
                    "El docente reescribió el enunciado. Conviene releerlo.")
            }
        }

        // Materiales
        for (id, now) in new.modules {
            guard let before = old.modules[id] else {
                add(.moduleAdded, now.name, "Material nuevo en la materia.")
                continue
            }
            let nuevos = Set(now.fileNames).subtracting(before.fileNames)
            if !nuevos.isEmpty {
                add(.fileAdded, now.name,
                    nuevos.count == 1
                        ? "Se subió “\(nuevos.first!)”."
                        : "Se subieron \(nuevos.count) archivos nuevos.")
            }
        }

        for (id, before) in old.modules where new.modules[id] == nil {
            add(.moduleRemoved, before.name, "Ya no está en la materia.")
        }

        return out
    }

    /// El texto que hace valiosa toda la función: no "cambió la fecha" sino
    /// cuántos días y para qué lado.
    private func dueDateText(from: Int?, to: Int?) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_NI")
        f.dateFormat = "d 'de' MMMM, HH:mm"

        guard let to, to > 0 else { return "Le quitaron la fecha de entrega." }
        let newDate = Date(timeIntervalSince1970: TimeInterval(to))

        guard let from, from > 0 else {
            return "Ahora tiene fecha de entrega: \(f.string(from: newDate))."
        }
        let oldDate = Date(timeIntervalSince1970: TimeInterval(from))
        let days = Int((newDate.timeIntervalSince(oldDate) / 86_400).rounded())

        let movimiento: String
        if days < 0 {
            movimiento = "se adelantó \(abs(days)) día\(abs(days) == 1 ? "" : "s")"
        } else if days > 0 {
            movimiento = "se corrió \(days) día\(days == 1 ? "" : "s")"
        } else {
            movimiento = "cambió de hora"
        }
        return "La entrega \(movimiento): \(f.string(from: oldDate)) → \(f.string(from: newDate))."
    }

    // MARK: Estado

    func markAllSeen() {
        guard unseenCount > 0 else { return }
        for i in changes.indices { changes[i].seen = true }
        persist()
    }

    func clear() {
        changes = []
        persist()
    }

    /// Olvida las fotos para volver a empezar. No borra el diario.
    func resetBaseline() {
        snapshots = [:]
        persist()
    }

    // MARK: Persistencia

    private func load() {
        if let d = defaults.data(forKey: changesKey),
           let decoded = try? JSONDecoder().decode([CourseChange].self, from: d) {
            changes = decoded
        }
        if let d = defaults.data(forKey: snapshotsKey),
           let decoded = try? JSONDecoder().decode([Int: CourseSnapshot].self, from: d) {
            snapshots = decoded
        }
        if let t = defaults.object(forKey: lastScanKey) as? Date { lastScan = t }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(changes) {
            defaults.set(d, forKey: changesKey)
        }
        if let d = try? JSONEncoder().encode(snapshots) {
            defaults.set(d, forKey: snapshotsKey)
        }
        defaults.set(lastScan, forKey: lastScanKey)
    }
}
