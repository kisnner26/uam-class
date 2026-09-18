import Foundation
import AppKit

// MARK: - Estudiar con tu materia
//
// El material que el docente subió, leído por Claude y respondido CON CITAS al
// archivo del que salió cada cosa.
//
// La diferencia con preguntarle a un chatbot cualquiera: acá la respuesta sale
// del PDF que tu docente subió, no del conocimiento general del modelo. Si algo
// no está en el material, la respuesta tiene que decirlo en vez de rellenar —
// que es exactamente el modo de fallar que arruina una guía de estudio.

@MainActor
enum StudyWorkspace {

    enum Mode: String, CaseIterable, Identifiable {
        case ask        // pregunta libre
        case explain    // explicame esto
        case guide      // guía de estudio
        case practice   // preguntas de práctica
        case flashcards // tarjetas de repaso
        case compare    // A contra B
        case exam       // qué entra en el examen
        case digest     // resumen del material

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ask:        return "Preguntar"
            case .explain:    return "Explicame"
            case .guide:      return "Guía de estudio"
            case .practice:   return "Práctica"
            case .flashcards: return "Tarjetas"
            case .compare:    return "Comparar"
            case .exam:       return "Qué entra"
            case .digest:     return "Resumen"
            }
        }

        var symbol: String {
            switch self {
            case .ask:        return "questionmark.bubble"
            case .explain:    return "lightbulb"
            case .guide:      return "list.bullet.rectangle"
            case .practice:   return "checkmark.square"
            case .flashcards: return "rectangle.on.rectangle"
            case .compare:    return "arrow.left.arrow.right"
            case .exam:       return "graduationcap"
            case .digest:     return "doc.text.magnifyingglass"
            }
        }

        /// Modos que no tienen sentido sin que escribas algo.
        var needsQuestion: Bool {
            self == .ask || self == .explain || self == .compare
        }

        var placeholder: String {
            switch self {
            case .ask:        return "¿Qué querés saber del material?"
            case .explain:    return "Tema que querés que te expliquen"
            case .guide:      return "Tema en el que enfocar la guía (opcional)"
            case .practice:   return "Tema del examen de práctica (opcional)"
            case .flashcards: return "Tema de las tarjetas (opcional)"
            case .compare:    return "Dos conceptos separados por «vs»"
            case .exam:       return "Corte o unidad (opcional)"
            case .digest:     return "Qué resumir (opcional)"
            }
        }

        /// Cómo se llama el archivo que va a producir.
        var outputName: String {
            switch self {
            case .ask:        return "RESPUESTA.md"
            case .explain:    return "EXPLICACION.md"
            case .guide:      return "GUIA-DE-ESTUDIO.md"
            case .practice:   return "PRACTICA.md"
            case .flashcards: return "TARJETAS.md"
            case .compare:    return "COMPARACION.md"
            case .exam:       return "QUE-ENTRA.md"
            case .digest:     return "RESUMEN.md"
            }
        }
    }

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("UAMClass/Estudio", isDirectory: true)
    }

    static func folder(for course: MoodleCourse) -> URL {
        let info = CourseInfo(course: course)
        return root.appendingPathComponent("\(info.code) · \(info.name)", isDirectory: true)
    }

    static func materialsFolder(for course: MoodleCourse) -> URL {
        folder(for: course).appendingPathComponent("materiales", isDirectory: true)
    }

    /// Cuántos archivos hay ya bajados de esa materia.
    static func materialCount(for course: MoodleCourse) -> Int {
        let dir = materialsFolder(for: course)
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { !$0.hasPrefix(".") }.count ?? 0
    }

    /// Prepara la carpeta: baja el material y deja escrito el índice del curso.
    @discardableResult
    static func prepare(course: MoodleCourse, moodle: MoodleClient) async throws -> CourseMaterials.Result {
        let dir = folder(for: course)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Se baja más material que para una tarea: acá el material ES el objeto.
        let result = await CourseMaterials.pull(course: course,
                                                into: materialsFolder(for: course),
                                                moodle: moodle,
                                                limit: 40,
                                                maxBytes: 200_000_000)

        let info = CourseInfo(course: course)
        var index = """
        # \(info.code) — \(info.name)

        Material descargado: \(result.downloaded) archivo\(result.downloaded == 1 ? "" : "s") en `materiales/`.
        """
        if result.skipped > 0 {
            index += "\nNo se bajaron \(result.skipped) (muy pesados o fuera del tope)."
        }
        index += "\n\n## Contenido de la materia en Moodle\n\n"
        index += result.index.joined(separator: "\n")

        try index.write(to: dir.appendingPathComponent("MATERIA.md"),
                        atomically: true, encoding: .utf8)
        return result
    }

    // MARK: El encargo

    static func prompt(mode: Mode, question: String, course: MoodleCourse) -> String {
        let info = CourseInfo(course: course)
        let head = """
        Sos el asistente de estudio de un estudiante de la Universidad Americana \
        (UAM) para la materia \(info.code) — \(info.name).

        ## Con qué trabajás

        - `MAPA.md` — el mapa de la materia: qué temas hay y en qué archivo y \
        página vive cada uno. **Leelo SIEMPRE primero.** Está para que no tengas \
        que explorar a ciegas.
        - `indice/*.txt` — el texto plano de todo el material, ya extraído de los \
        PDFs, con marcas `[[p.N]]` que indican la página del original.
        - `INDICE.md` — qué archivo es cada `.txt`, cuántas páginas tiene y qué \
        títulos contiene.
        - `MATERIA.md` — el contenido del curso en Moodle, incluido lo que no se \
        pudo descargar.

        ## Método — importa el orden

        1. **Leé `MAPA.md`.** En dos mil caracteres te dice dónde está todo.
        2. **`Grep` sobre `indice/`**, nunca sobre `materiales/`. Los `.txt` \
        tienen el mismo contenido que los PDFs y se leen al instante; abrir un \
        PDF cuesta decenas de veces más y no agrega nada.
        3. Recién ahí, `Read` con `offset`/`limit` sobre el `.txt` que importa. \
        Leer un archivo entero para contestar una pregunta es desperdicio.
        4. **No abras `materiales/` nunca.** Si algo no está en `indice/`, es que \
        no se pudo extraer: decilo, no lo inventes.

        ## Reglas

        - Toda afirmación va con su fuente: **archivo y página**, tomando el \
        número de la marca `[[p.N]]` más cercana. Formato `(archivo.pdf, p. 12)`.
        - Si el material NO cubre algo, decilo con todas las letras: \
        "esto no está en el material de la materia". Podés agregar contexto \
        general aparte, pero **marcado como tal**. Una guía con relleno inventado \
        es peor que una guía corta.
        - En español, claro y directo. Sin adular ni adornar.

        """

        let body: String
        switch mode {
        case .ask:
            body = """
            ## Tu tarea

            Respondé esta pregunta del estudiante:

            > \(question)

            Escribí la respuesta en `RESPUESTA.md`. Estructura: la respuesta \
            directa primero, después el desarrollo, y al final una sección \
            **Dónde lo dice** con las citas exactas.
            """
        case .guide:
            let focus = question.trimmingCharacters(in: .whitespaces)
            body = """
            ## Tu tarea

            Armá una guía de estudio en `GUIA-DE-ESTUDIO.md`\
            \(focus.isEmpty ? " sobre todo el material disponible." : " enfocada en: \(focus).")

            Estructura:
            - **Mapa del tema** — qué entra y cómo se conecta, en un párrafo.
            - **Lo esencial** — los conceptos que hay que saber sí o sí, cada uno \
            explicado en 2-4 líneas y con su fuente.
            - **Detalles que se preguntan** — definiciones, clasificaciones, \
            cifras concretas que aparecen en el material.
            - **Lo que más se confunde** — pares de conceptos parecidos, con la \
            diferencia explicada.
            - **Dónde estudiar cada cosa** — qué archivo y qué parte, para ir al \
            original.
            """
        case .practice:
            let focus = question.trimmingCharacters(in: .whitespaces)
            body = """
            ## Tu tarea

            Escribí un examen de práctica en `PRACTICA.md`\
            \(focus.isEmpty ? "." : " sobre: \(focus).")

            - 15 preguntas sacadas **del material real**, no de conocimiento \
            general. Mezclá opción múltiple, verdadero/falso con justificación, \
            y dos o tres de desarrollo.
            - Ordenadas de más fácil a más difícil.
            - La sección **Respuestas** va AL FINAL, después de una línea `---`, \
            para poder resolverlo sin espiar.
            - Cada respuesta lleva su fuente y una explicación de una línea de \
            por qué las otras opciones no van.
            """
        case .digest:
            let focus = question.trimmingCharacters(in: .whitespaces)
            body = """
            ## Tu tarea

            Escribí en `RESUMEN.md` un resumen del material\
            \(focus.isEmpty ? "." : ", enfocado en: \(focus).")

            Un resumen por archivo (qué es, qué cubre, cuánto pesa en el curso), \
            y arriba de todo un párrafo de síntesis: si alguien solo pudiera leer \
            una cosa antes del examen, qué debería ser y por qué.
            """

        case .explain:
            body = """
            ## Tu tarea

            Explicá esto como si el estudiante lo viera por primera vez:

            > \(question)

            Escribilo en `EXPLICACION.md`, en este orden:
            1. **La idea en una frase.** Sin jerga.
            2. **Por qué existe** — qué problema resuelve o para qué sirve.
            3. **Cómo funciona**, paso a paso, cada paso con su fuente.
            4. **Una analogía** con algo cotidiano. Una sola, y avisá que es tuya \
            y no del material.
            5. **El error típico** — qué es lo que casi todos entienden mal acá.
            """

        case .flashcards:
            let focus = question.trimmingCharacters(in: .whitespaces)
            body = """
            ## Tu tarea

            Escribí tarjetas de repaso en `TARJETAS.md`\
            \(focus.isEmpty ? "." : " sobre: \(focus).")

            - Entre 20 y 30 tarjetas, formato `**P:** …` y en la línea siguiente \
            `**R:** …`, separadas por una línea en blanco.
            - Cada respuesta en UNA frase. Una tarjeta que hay que leer dos veces \
            no sirve para repasar.
            - Una pregunta por concepto, no varias mezcladas.
            - La fuente va al final de la respuesta, entre paréntesis.
            - Ordenadas por tema, con un `##` por bloque.
            """

        case .compare:
            body = """
            ## Tu tarea

            Compará estos conceptos: **\(question)**

            Escribí `COMPARACION.md` con:
            - Una **tabla** con los criterios que de verdad los distinguen \
            (elegilos vos según el material, no uses criterios genéricos).
            - Debajo, **en qué se parecen** — normalmente es lo que causa la \
            confusión.
            - **Cómo distinguirlos en un examen**: la señal concreta que te dice \
            cuál es cuál.
            - Si el material solo cubre uno de los dos, decilo antes que nada.
            """

        case .exam:
            let focus = question.trimmingCharacters(in: .whitespaces)
            body = """
            ## Tu tarea

            Escribí en `QUE-ENTRA.md` qué es lo que hay que estudiar\
            \(focus.isEmpty ? "." : " para: \(focus).")

            Basate en señales REALES del material: lo que el programa marca como \
            contenido evaluable, lo que el docente repite, lo que tiene más \
            páginas dedicadas, lo que aparece en objetivos de aprendizaje.

            Estructura:
            - **Casi seguro que entra** — con la señal que lo indica y su fuente.
            - **Probable** — y por qué.
            - **Poco probable** — para que no pierdas tiempo ahí.
            - **No puedo saberlo** — lo que el material no permite deducir. \
            Sé honesto acá: inventar un temario da una falsa seguridad que se \
            paga en el examen.
            """
        }
        return head + body
    }

    /// El encargo que construye el mapa. Corre UNA vez por materia.
    ///
    /// Es la inversión que abarata todo lo demás: en vez de que cada consulta
    /// descubra la estructura del curso desde cero, se descubre una vez y queda
    /// escrita. Después, cada pregunta arranca sabiendo dónde buscar.
    static func mapPrompt(course: MoodleCourse) -> String {
        let info = CourseInfo(course: course)
        return """
        Sos el asistente de estudio de \(info.code) — \(info.name), de la
        Universidad Americana (UAM).

        Tu tarea es construir **el mapa de la materia**: un solo archivo que le
        permita a cualquier consulta futura saber dónde está cada cosa sin tener
        que explorar todo otra vez.

        ## Cómo trabajar

        1. Leé `INDICE.md`: te dice qué archivo es cada `.txt` y qué contiene.
        2. Recorré los `.txt` de `indice/`. Podés leerlos enteros — esta es la
        única corrida que se puede permitir ese lujo, porque es la que evita que
        todas las siguientes tengan que hacerlo.
        3. **No abras `materiales/`.** El texto ya está extraído.

        ## Qué escribir en `MAPA.md`

        Apuntá a unos 2.000 caracteres. Es un mapa, no un resumen: tiene que
        decir DÓNDE está cada cosa, no explicarla.

        - **De qué trata la materia** — dos o tres líneas.
        - **Temas**, uno por viñeta. Cada uno con el archivo y el rango de
        páginas donde vive. Formato: `Tema — archivo.pdf, p. 4-9`.
        - **Términos clave**, con el archivo donde se definen. Sirve para que una
        búsqueda posterior sepa qué palabra buscar.
        - **Estructura de la evaluación**, si el material la trae: cortes,
        fechas, puntajes.
        - **Huecos** — qué temas menciona el programa pero no están en ningún
        archivo descargado. Esto es lo más valioso del mapa: evita que las
        consultas futuras busquen algo que no existe.

        Denso y telegráfico. Este archivo se va a leer en cada consulta, así que
        cada línea tiene que ganarse el lugar.
        """
    }

    static func output(mode: Mode, course: MoodleCourse) -> URL {
        folder(for: course).appendingPathComponent(mode.outputName)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
