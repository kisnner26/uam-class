import Foundation
import SwiftUI

/// Cache local de datos Moodle en Application Support.
/// Se usa como fallback cuando el server no responde ("modo offline").
@MainActor
final class OfflineCache {
    static let shared = OfflineCache()

    private let root: URL
    private let fm = FileManager.default

    /// Cache por cuenta.
    ///
    /// Con dos cuentas abiertas a la vez, un cache compartido haría que la
    /// ventana B pisara las materias de la A y que al abrir offline te
    /// aparecieran las materias de otra persona. Cada cuenta escribe en su
    /// propio subdirectorio; `nil` = la carpeta raíz de siempre (ventana
    /// principal y migración de instalaciones previas).
    init(scope: String? = nil) {
        var base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("UAMClass", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        if let scope, !scope.isEmpty {
            base = base.appendingPathComponent(Self.slug(scope), isDirectory: true)
        }
        try? fm.createDirectory(at: base.appendingPathComponent("images"),
                                withIntermediateDirectories: true)
        self.root = base
    }

    /// El id de cuenta trae `::` y otros caracteres que no quiero en una ruta.
    private static func slug(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    // MARK: - Cursos

    func saveCourses(_ courses: [MoodleCourse]) {
        save(courses, to: "courses.json")
    }
    func loadCourses() -> [MoodleCourse]? {
        load([MoodleCourse].self, from: "courses.json")
    }

    // MARK: - Contents por curso

    func saveContents(_ sections: [MoodleCourseSection], courseId: Int) {
        save(sections, to: "contents-\(courseId).json")
    }
    func loadContents(courseId: Int) -> [MoodleCourseSection]? {
        load([MoodleCourseSection].self, from: "contents-\(courseId).json")
    }

    // MARK: - Assignments

    func saveAssignments(_ resp: MoodleAssignmentsResponse, key: String) {
        save(resp, to: "assignments-\(key).json")
    }
    func loadAssignments(key: String) -> MoodleAssignmentsResponse? {
        load(MoodleAssignmentsResponse.self, from: "assignments-\(key).json")
    }

    // MARK: - Grades

    func saveGrades(_ resp: MoodleGradesResponse, courseId: Int) {
        save(resp, to: "grades-\(courseId).json")
    }
    func loadGrades(courseId: Int) -> MoodleGradesResponse? {
        load(MoodleGradesResponse.self, from: "grades-\(courseId).json")
    }

    // MARK: - Imagen (por URL hash)

    func imagePath(for url: String) -> URL {
        let hash = String(url.hash)
        return root.appendingPathComponent("images", isDirectory: true)
                   .appendingPathComponent("\(hash).data")
    }

    func loadImage(for url: String) -> PlatformImage? {
        let path = imagePath(for: url)
        guard fm.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path) else { return nil }
        return PlatformImage(data: data)
    }

    func saveImage(_ data: Data, for url: String) {
        let path = imagePath(for: url)
        try? data.write(to: path)
    }

    // MARK: - Info general

    /// Tamaño total del cache (bytes).
    func totalSize() -> Int64 {
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    func clear() {
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root.appendingPathComponent("images"),
                                withIntermediateDirectories: true)
    }

    #if os(macOS)
    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
    #endif

    // MARK: - Helpers

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = root.appendingPathComponent(filename)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = root.appendingPathComponent(filename)
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
