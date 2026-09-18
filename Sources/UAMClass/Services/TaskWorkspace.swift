import Foundation
import AppKit

// MARK: - Taller de tareas
//
// Prepara la carpeta donde Claude va a trabajar. La idea es que Claude no
// adivine nada: se le deja el enunciado completo, los adjuntos del docente ya
// descargados, y las reglas de la UAM escritas.
//
// Todo vive en Application Support, una carpeta por tarea. Nada se sube solo:
// lo que salga de acá queda esperando tu revisión.

@MainActor
enum TaskWorkspace {

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("UAMClass/Borradores", isDirectory: true)
    }

    static func folder(for assignment: MoodleAssignment, course: MoodleCourse?) -> URL {
        let code = course.map { CourseInfo(course: $0).code } ?? "curso"
        let safe = HTMLClean.plain(assignment.name)
            .replacingOccurrences(of: "/", with: "-")
            .prefix(50)
            .trimmingCharacters(in: .whitespaces)
        return root.appendingPathComponent("\(code) · \(safe) (\(assignment.id))",
                                           isDirectory: true)
    }

    /// Deja la carpeta lista: enunciado en Markdown + adjuntos descargados.
    /// Devuelve la carpeta y cuántos adjuntos se pudieron traer.
    @discardableResult
    static func prepare(assignment: MoodleAssignment,
                        course: MoodleCourse?,
                        moodle: MoodleClient) async throws -> (URL, Int) {
        let dir = folder(for: assignment, course: course)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Los adjuntos van a una subcarpeta para que Claude no los confunda con
        // lo que él mismo produce.
        let attachDir = dir.appendingPathComponent("consigna", isDirectory: true)
        try FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)

        var downloaded = 0
        for file in assignment.introattachments ?? [] {
            guard let raw = file.fileurl,
                  let url = await moodle.tokenizedURL(from: raw),
                  let name = file.filename, !name.isEmpty else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try data.write(to: attachDir.appendingPathComponent(name))
                downloaded += 1
            } catch {
                // Un adjunto que no baja no debería frenar el resto.
                continue
            }
        }

        // Los materiales del curso. Esto vino de ver fallar el primer caso
        // real: la consigna decía "orientaciones en la guía didáctica S1", y esa
        // guía no era adjunto de la tarea sino un recurso suelto del curso. Sin
        // traerla, Claude inventaba la estructura del trabajo entero.
        var materials: [String] = []
        if let course {
            (materials, downloaded) = await pullMaterials(course: course,
                                                          into: dir,
                                                          moodle: moodle,
                                                          already: downloaded)
        }

        try brief(assignment: assignment, course: course,
                  attachments: downloaded, materials: materials)
            .write(to: dir.appendingPathComponent("ENUNCIADO.md"),
                   atomically: true, encoding: .utf8)

        return (dir, downloaded)
    }

    /// Índice del material del curso + descarga de los documentos.
    /// La mecánica vive en `CourseMaterials`, compartida con la vista de estudio.
    private static func pullMaterials(course: MoodleCourse,
                                      into dir: URL,
                                      moodle: MoodleClient,
                                      already: Int) async -> ([String], Int) {
        let result = await CourseMaterials.pull(
            course: course,
            into: dir.appendingPathComponent("materiales", isDirectory: true),
            moodle: moodle)
        return (result.index, already + result.downloaded)
    }


    /// El enunciado tal como lo va a leer Claude.
    private static func brief(assignment: MoodleAssignment,
                              course: MoodleCourse?,
                              attachments: Int,
                              materials: [String]) -> String {
        let info = course.map { CourseInfo(course: $0) }
        let statement = HTMLClean.plain(assignment.intro)
        // Con locale explícito: sin esto la fecha salía en inglés
        // ("Wednesday, 26 August") dentro de un documento en español.
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_NI")
        df.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        let due = assignment.dueDateOrNil.map { df.string(from: $0) } ?? "sin fecha"

        var out = """
        # \(HTMLClean.plain(assignment.name))

        - **Materia:** \(info.map { "\($0.code) — \($0.name)" } ?? "—")
        - **Grupo:** \(info?.group ?? "—")
        - **Entrega:** \(due)
        - **Puntaje:** \(assignment.grade.map { String(format: "%.0f", $0) } ?? "—")

        ## Consigna del docente

        """

        out += statement.isEmpty
            ? "_El docente no escribió consigna en Moodle. Mirá los archivos de `consigna/`._"
            : statement

        if attachments > 0 {
            out += """


            ## Archivos disponibles

            Hay \(attachments) archivo\(attachments == 1 ? "" : "s") descargado\(attachments == 1 ? "" : "s") en `consigna/` y `materiales/`.
            Leelos ANTES de escribir nada: ahí suelen estar la rúbrica, el formato
            exigido y las guías didácticas que la consigna menciona sin adjuntar.
            """
        }

        if !materials.isEmpty {
            out += """


            ## Todo el material del curso

            Esta es la lista completa de lo que hay en la materia. Si la consigna
            nombra algo de acá (una guía, una lectura, una semana), buscalo primero
            en `materiales/`; si no está descargado, decilo en las notas en vez de
            inventar su contenido.

            """
            out += materials.joined(separator: "\n")
        }
        return out
    }

    // MARK: El encargo

    /// Las instrucciones que recibe Claude.
    ///
    /// Están escritas para maximizar dos cosas a la vez: la calidad del trabajo
    /// y la capacidad del estudiante de revisarlo. De ahí el archivo de notas
    /// obligatorio — sin él, revisar un texto largo es leerlo entero de nuevo
    /// sin saber dónde mirar.
    static func prompt(assignment: MoodleAssignment, course: MoodleCourse?) -> String {
        let info = course.map { CourseInfo(course: $0) }
        return """
        Sos un estudiante universitario de la Universidad Americana (UAM), \
        Managua, Nicaragua. Tenés que resolver una tarea de la materia \
        \(info.map { "\($0.code) — \($0.name)" } ?? "asignada").

        ## Qué hay en esta carpeta

        - `ENUNCIADO.md` — la consigna, el puntaje y la fecha de entrega.
        - `consigna/` — los archivos que adjuntó el docente, si los hay.

        ## Qué tenés que hacer

        1. Leé `ENUNCIADO.md` COMPLETO y todos los archivos de `consigna/`. \
        Si la consigna pide un formato, una extensión o una estructura \
        determinada, eso manda por encima de cualquier criterio propio.
        2. Resolvé la tarea con la mayor calidad que puedas. Trabajo terminado, \
        no un esquema: si pide un ensayo, escribí el ensayo entero; si pide \
        código, que compile; si pide un análisis, desarrollalo.
        3. **Antes de escribir el entregable**, creá `NOTAS-PARA-REVISAR.md` con \
        lo que interpretaste y las decisiones que vas a tomar. Al terminar, \
        volvé y completalo. Va primero a propósito: si la corrida se corta a la \
        mitad, lo único que no se puede perder es el registro de en qué te \
        basaste.
        4. Escribí el entregable en esta carpeta, con un nombre claro y **en un \
        formato entregable de verdad** (ver abajo). Markdown NO es un formato de \
        entrega.

        ## Formato del entregable

        Nadie entrega un `.md` en la universidad. El archivo final tiene que ser \
        el formato que se usaría de verdad:

        - **Si la consigna pide un formato, ese manda.** Word, PDF, Excel, \
        presentación, lo que diga.
        - **Si no lo dice, elegilo vos** según lo que sea el trabajo:
          - Ensayo, informe, análisis, propuesta, monografía → **.docx**
          - Algo que se imprime, se firma o donde la maquetación importa → **.pdf**
          - Datos, presupuesto, matriz, cronograma → **.xlsx**
          - Exposición → **.pptx**
          - Programación → los archivos fuente que corresponda, más un README

        Herramientas disponibles en esta Mac (verificadas — no pierdas tiempo \
        con otras):

        - `python3` con **python-docx** (Word con estilos reales) y **reportlab** (PDF).
        - `textutil` de macOS: `textutil -convert docx entrada.html -output salida.docx`. \
        Sirve bien escribiendo primero un HTML con la estructura.
        - **No hay pandoc ni LibreOffice.** No los invoques.
        - Si tenés disponible la skill `uam-docx`, usala para Word: da el formato \
        institucional de la UAM con portada e índice.

        Podés dejar un `.md` de trabajo si te sirve, pero el entregable final va \
        en su formato. Al terminar, verificá que el archivo exista y no esté \
        vacío — un `.docx` de 0 bytes se entrega sin que nadie lo note.

        ## Reglas que no se negocian

        - **En español de Nicaragua**, registro académico, voseo solo si la \
        consigna es informal.
        - **No inventes datos, citas, autores ni estadísticas.** Si necesitás un \
        dato que no tenés, dejalo marcado como `[VERIFICAR: …]` en el texto y \
        anotalo en las notas. Un dato inventado es peor que un espacio en blanco: \
        el estudiante lo entrega sin saber que es falso.
        - Si algo de la consigna es ambiguo, elegí la interpretación más \
        razonable, seguí adelante, y **decilo en las notas**. No te frenes a \
        preguntar: nadie va a contestarte.
        - No agregues relleno para alcanzar una extensión. Si te falta sustancia, \
        decilo en las notas.

        ## El archivo de notas

        `NOTAS-PARA-REVISAR.md` es lo que el estudiante va a leer ANTES de \
        entregar. Tiene que responder, en viñetas cortas:

        - Qué interpretaste de la consigna y qué decisiones tomaste.
        - Qué partes son las más flojas o las que más conviene revisar.
        - Todo `[VERIFICAR: …]` que dejaste, y por qué.
        - Qué habría que agregarle o cambiarle para que sea claramente tuyo.

        Sé honesto en ese archivo. Su utilidad depende de eso.
        """
    }

    /// Extensiones que se entregan de verdad. Un `.md` de trabajo no va a
    /// Moodle: si Claude lo dejó, es un borrador intermedio, no el entregable.
    private static let deliverable: Set<String> = [
        "docx", "doc", "pdf", "xlsx", "xls", "pptx", "ppt", "rtf", "odt",
        "csv", "zip", "swift", "py", "js", "ts", "java", "c", "cpp", "sql",
        "ipynb", "png", "jpg", "jpeg"
    ]

    /// Lo que corresponde subir a Moodle.
    ///
    /// Si no hay ningún archivo en formato entregable, se devuelve vacío a
    /// propósito: es mejor que el panel avise a que suba un `.md` que el docente
    /// no va a poder abrir.
    static func deliverables(in dir: URL) -> [URL] {
        outputs(in: dir).filter {
            $0.lastPathComponent != "NOTAS-PARA-REVISAR.md"
            && deliverable.contains($0.pathExtension.lowercased())
        }
    }

    /// Archivos de trabajo: el `.md` intermedio, el script que armó el `.docx`.
    /// Sirven mientras Claude trabaja y estorban después.
    ///
    /// Nunca incluye las notas ni nada en formato entregable: borrar el trabajo
    /// por accidente con un botón de "limpiar" sería el peor final posible.
    static func scraps(in dir: URL) -> [URL] {
        let deliverables = Set(deliverables(in: dir).map(\.lastPathComponent))
        return outputs(in: dir).filter { url in
            let name = url.lastPathComponent
            guard name != "NOTAS-PARA-REVISAR.md" else { return false }
            guard !deliverables.contains(name) else { return false }
            return true
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Los archivos que produjo Claude, sin contar lo que le dejamos nosotros.
    static func outputs(in dir: URL) -> [URL] {
        let skip: Set<String> = ["ENUNCIADO.md", "consigna", ".DS_Store"]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { !skip.contains($0.lastPathComponent) }
            // Solo archivos: si Claude crea una subcarpeta, leerla como `Data`
            // para subirla tiraría un error.
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?
                        .isRegularFile == true }
            .sorted { a, b in
                // Las notas primero: es lo que hay que leer antes de nada.
                if a.lastPathComponent == "NOTAS-PARA-REVISAR.md" { return true }
                if b.lastPathComponent == "NOTAS-PARA-REVISAR.md" { return false }
                return a.lastPathComponent < b.lastPathComponent
            }
    }
}
