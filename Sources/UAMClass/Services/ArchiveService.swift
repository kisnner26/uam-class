import Foundation
import AppKit

/// Descarga el semestre completo a ~/Downloads/UAM Class/{periodo}-{año}/
/// con la estructura:
///   {Código - Nombre}/
///       {Sección}/
///           archivos…
///       Notas.csv
///       Foros/
///           {Nombre del foro}.md
@MainActor
final class ArchiveService: ObservableObject {

    struct Progress: Equatable {
        var currentCourse: String = ""
        var currentStep: String = ""
        var doneCourses: Int = 0
        var totalCourses: Int = 0
        var doneFiles: Int = 0
        var totalFiles: Int = 0
        var isRunning: Bool = false
        var finishedFolder: URL? = nil
        var errors: [String] = []
    }

    @Published var progress = Progress()
    private var cancelled = false

    private let moodle: MoodleClient
    init(moodle: MoodleClient) { self.moodle = moodle }

    func cancel() { cancelled = true }

    // MARK: - Top-level

    /// Ejecuta el archivo para los cursos indicados.
    func archive(courses: [MoodleCourse], userId: Int, periodLabel: String) async {
        cancelled = false
        progress = Progress()
        progress.isRunning = true
        progress.totalCourses = courses.count

        let root = rootFolder(periodLabel: periodLabel)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        catch {
            progress.errors.append("No pude crear la carpeta base: \(error.localizedDescription)")
            progress.isRunning = false
            return
        }

        // Primera pasada: contar archivos aprox para la barra
        for course in courses {
            if cancelled { break }
            do {
                let sections = try await moodle.courseContents(courseId: course.id)
                var n = 0
                for s in sections {
                    for m in s.modules {
                        n += (m.contents?.count ?? 0)
                    }
                }
                progress.totalFiles += n
            } catch { /* seguimos */ }
        }

        // Segunda pasada: bajar de verdad
        for course in courses {
            if cancelled { break }
            progress.currentCourse = CourseInfo(course: course).name

            let info = CourseInfo(course: course)
            let courseFolder = root.appendingPathComponent(safeName("\(info.code) - \(info.name)"))
            try? FileManager.default.createDirectory(at: courseFolder, withIntermediateDirectories: true)

            await archiveContent(courseFolder: courseFolder, course: course)
            await archiveGrades(courseFolder: courseFolder, course: course, userId: userId)
            await archiveForums(courseFolder: courseFolder, course: course)

            progress.doneCourses += 1
        }

        progress.finishedFolder = root
        progress.isRunning = false
    }

    // MARK: - Content (sections + files)

    private func archiveContent(courseFolder: URL, course: MoodleCourse) async {
        progress.currentStep = "Contenido"
        let sections: [MoodleCourseSection]
        do {
            sections = try await moodle.courseContents(courseId: course.id)
        } catch {
            progress.errors.append("[\(CourseInfo(course: course).code)] contenidos: \(error.localizedDescription)")
            return
        }

        // Índice
        var indexLines: [String] = ["# \(course.fullname)\n"]

        for (i, section) in sections.enumerated() {
            if cancelled { return }
            let secName = safeName("\(String(format: "%02d", i)) - \(section.displayName)")
            let secFolder = courseFolder.appendingPathComponent(secName)
            try? FileManager.default.createDirectory(at: secFolder, withIntermediateDirectories: true)

            indexLines.append("## \(section.displayName)")
            if !section.cleanSummary.isEmpty {
                indexLines.append(section.cleanSummary + "\n")
            }

            for module in section.modules {
                indexLines.append("- **\(module.displayName)** _(\(module.modname))_")
                if let files = module.contents, !files.isEmpty {
                    let modFolder = secFolder.appendingPathComponent(safeName(module.displayName))
                    try? FileManager.default.createDirectory(at: modFolder, withIntermediateDirectories: true)

                    for file in files where (file.type ?? "file") == "file" {
                        if cancelled { return }
                        await downloadFile(file: file, into: modFolder)
                    }
                }
                if let url = module.url {
                    indexLines.append("  - Link: \(url)")
                }
            }
            indexLines.append("")
        }

        let index = indexLines.joined(separator: "\n")
        try? index.write(to: courseFolder.appendingPathComponent("Índice.md"),
                         atomically: true, encoding: .utf8)
    }

    private func downloadFile(file: MoodleContentFile, into folder: URL) async {
        guard let url = file.fileurl, let name = file.filename else {
            progress.doneFiles += 1
            return
        }
        progress.currentStep = name

        let dest = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            progress.doneFiles += 1
            return
        }
        do {
            let tmp = try await moodle.downloadFile(fileurl: url)
            try? FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            progress.errors.append("Archivo \(name): \(error.localizedDescription)")
        }
        progress.doneFiles += 1
    }

    // MARK: - Grades

    private func archiveGrades(courseFolder: URL, course: MoodleCourse, userId: Int) async {
        progress.currentStep = "Notas"
        do {
            let resp = try await moodle.gradeItems(courseId: course.id, userId: userId)
            guard let items = resp.usergrades.first?.gradeitems, !items.isEmpty else { return }
            var csv = "Ítem,Nota,Porcentaje,Estado,Comentario\n"
            for it in items {
                let name = it.displayName.replacingOccurrences(of: "\"", with: "'")
                let grade = it.displayGrade
                let pct = it.percentageformatted ?? ""
                let badge = it.badge?.label ?? ""
                let fb = it.cleanFeedback.replacingOccurrences(of: "\"", with: "'")
                                          .replacingOccurrences(of: "\n", with: " ")
                csv.append("\"\(name)\",\"\(grade)\",\"\(pct)\",\"\(badge)\",\"\(fb)\"\n")
            }
            let dest = courseFolder.appendingPathComponent("Notas.csv")
            try csv.data(using: .utf8)?.write(to: dest)
        } catch {
            progress.errors.append("[\(CourseInfo(course: course).code)] notas: \(error.localizedDescription)")
        }
    }

    // MARK: - Forums

    private func archiveForums(courseFolder: URL, course: MoodleCourse) async {
        progress.currentStep = "Foros"
        do {
            let forums = try await moodle.forumsByCourse(courseId: course.id)
            guard !forums.isEmpty else { return }
            let forumsFolder = courseFolder.appendingPathComponent("Foros")
            try? FileManager.default.createDirectory(at: forumsFolder, withIntermediateDirectories: true)

            for forum in forums {
                if cancelled { return }
                var md = "# \(forum.name)\n\n"
                if !forum.cleanIntro.isEmpty { md.append(forum.cleanIntro + "\n\n") }

                let discussions = (try? await moodle.discussions(forumId: forum.id))?.discussions ?? []
                for d in discussions {
                    md.append("## \(d.name)\n")
                    if let author = d.userfullname { md.append("_por \(author)_") }
                    if let when = d.when { md.append(" — \(when)") }
                    md.append("\n\n")
                    if !d.cleanMessage.isEmpty { md.append(d.cleanMessage + "\n\n") }
                    let posts = (try? await moodle.posts(discussionId: d.discussionId))?.posts ?? []
                    for p in posts.dropFirst() { // el primero suele ser el original
                        md.append("> **\(p.author?.fullname ?? "Anónimo")**")
                        if let w = p.when { md.append(" · \(w)") }
                        md.append("\n> \n")
                        for line in p.cleanMessage.split(separator: "\n") {
                            md.append("> \(line)\n")
                        }
                        md.append("\n")
                    }
                }

                let dest = forumsFolder.appendingPathComponent(safeName(forum.name) + ".md")
                try? md.data(using: .utf8)?.write(to: dest)
            }
        } catch {
            progress.errors.append("[\(CourseInfo(course: course).code)] foros: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func rootFolder(periodLabel: String) -> URL {
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        return downloads.appendingPathComponent("UAM Class", isDirectory: true)
            .appendingPathComponent(safeName(periodLabel), isDirectory: true)
    }

    private func safeName(_ s: String) -> String {
        var out = s
        for bad in ["/", ":", "\\", "?", "*", "|", "<", ">", "\""] {
            out = out.replacingOccurrences(of: bad, with: "-")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
