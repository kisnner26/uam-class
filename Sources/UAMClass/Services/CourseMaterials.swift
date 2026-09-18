import Foundation

// MARK: - Materiales del curso
//
// Descarga a disco lo que el docente subió a la materia. Lo usan dos funciones
// que llegaron por caminos distintos y necesitan lo mismo:
//
//  · Resolver una tarea (`TaskWorkspace`), donde la consigna suele remitir a
//    una guía que no está adjunta a la tarea sino suelta en el curso.
//  · Estudiar (`StudyWorkspace`), donde el material ES el objeto de estudio.
//
// Se bajan solo documentos y con tope: una materia con videos pesa gigas y
// bajarla entera tardaría más que leerla.

@MainActor
enum CourseMaterials {

    struct Result {
        var downloaded: Int = 0
        /// Índice legible de TODO lo que hay en la materia, esté descargado o no.
        var index: [String] = []
        var skipped: Int = 0
    }

    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "ppt", "pptx", "txt", "md", "rtf",
        "xls", "xlsx", "csv", "odt", "odp"
    ]

    static func isDocument(_ name: String) -> Bool {
        documentExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Baja los documentos del curso a `into` y devuelve el índice completo.
    ///
    /// - Parameters:
    ///   - limit: cuántos archivos como máximo.
    ///   - maxBytes: presupuesto total de descarga.
    static func pull(course: MoodleCourse,
                     into folder: URL,
                     moodle: MoodleClient,
                     limit: Int = 12,
                     maxBytes: Int = 60_000_000) async -> Result {
        var out = Result()
        guard let sections = try? await moodle.courseContents(courseId: course.id) else {
            return out
        }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var budget = limit
        var bytes = 0

        for section in sections {
            let visible = section.modules.filter { $0.visible != 0 }
            guard !visible.isEmpty else { continue }
            out.index.append("### \(section.displayName)")

            for module in visible {
                out.index.append("- \(module.displayName) _(\(module.modname))_")

                for file in module.contents ?? [] {
                    guard let name = file.filename, isDocument(name) else { continue }
                    guard budget > 0 else { out.skipped += 1; continue }

                    // Un solo archivo enorme no debería comerse el presupuesto.
                    if let size = file.filesize, size > 25_000_000 {
                        out.skipped += 1
                        continue
                    }
                    let target = folder.appendingPathComponent(name)
                    // Ya descargado en una corrida anterior: no se vuelve a bajar.
                    if FileManager.default.fileExists(atPath: target.path) {
                        budget -= 1
                        out.downloaded += 1
                        continue
                    }
                    guard let raw = file.fileurl,
                          let url = await moodle.tokenizedURL(from: raw) else { continue }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        guard bytes + data.count < maxBytes else { budget = 0; break }
                        try data.write(to: target)
                        bytes += data.count
                        budget -= 1
                        out.downloaded += 1
                    } catch {
                        continue
                    }
                }
            }
        }
        return out
    }
}
