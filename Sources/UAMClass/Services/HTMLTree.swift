import Foundation

// MARK: - Mini árbol HTML
//
// Moodle manda cada pregunta como HTML ya renderizado, así que para responder
// nativamente hay que leer los `<input>`, `<select>` y `<textarea>` reales con
// sus atributos `name` exactos. Con regex eso es un desastre — un `>` dentro de
// un atributo ya rompe todo — así que hay un tokenizador de verdad.
//
// No pretende ser un parser HTML5 conforme: alcanza con manejar el subconjunto
// que emite Moodle (tags bien formados, atributos con y sin comillas, void
// elements, y `<script>`/`<style>` a ignorar).

final class HTMLNode {
    enum Kind {
        case element(tag: String, attributes: [String: String])
        case text(String)
    }

    let kind: Kind
    private(set) var children: [HTMLNode] = []
    weak var parent: HTMLNode?

    init(kind: Kind) { self.kind = kind }

    func append(_ child: HTMLNode) {
        child.parent = self
        children.append(child)
    }

    // MARK: Accesores

    var tag: String? {
        if case .element(let t, _) = kind { return t }
        return nil
    }

    var attributes: [String: String] {
        if case .element(_, let a) = kind { return a }
        return [:]
    }

    func attr(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    var classes: [String] {
        (attr("class") ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    func hasClass(_ name: String) -> Bool {
        classes.contains(name)
    }

    /// Texto visible concatenado, con las entidades ya decodificadas.
    var innerText: String {
        var out = ""
        collectText(into: &out)
        return HTMLClean.decode(out)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n+ *", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collectText(into out: inout String) {
        switch kind {
        case .text(let s):
            out += s
        case .element(let tag, _):
            if tag == "script" || tag == "style" { return }
            if tag == "br" { out += "\n"; return }
            for c in children { c.collectText(into: &out) }
            if HTMLNode.blockTags.contains(tag) { out += "\n" }
        }
    }

    private static let blockTags: Set<String> = [
        "p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre"
    ]

    // MARK: Búsqueda

    /// Todos los descendientes (incluido self) que cumplen el predicado.
    func all(where predicate: (HTMLNode) -> Bool) -> [HTMLNode] {
        var out: [HTMLNode] = []
        if predicate(self) { out.append(self) }
        for c in children { out.append(contentsOf: c.all(where: predicate)) }
        return out
    }

    func first(where predicate: (HTMLNode) -> Bool) -> HTMLNode? {
        if predicate(self) { return self }
        for c in children {
            if let found = c.first(where: predicate) { return found }
        }
        return nil
    }

    func elements(tag: String) -> [HTMLNode] {
        all { $0.tag == tag }
    }

    func firstElement(class name: String) -> HTMLNode? {
        first { $0.hasClass(name) }
    }

    func elements(class name: String) -> [HTMLNode] {
        all { $0.hasClass(name) }
    }

    /// Ancestro más cercano que cumple el predicado.
    func closest(where predicate: (HTMLNode) -> Bool) -> HTMLNode? {
        var node = parent
        while let n = node {
            if predicate(n) { return n }
            node = n.parent
        }
        return nil
    }
}

// MARK: - Parser

enum HTMLTree {

    /// Elementos que nunca tienen cierre.
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    static func parse(_ html: String) -> HTMLNode {
        let root = HTMLNode(kind: .element(tag: "#root", attributes: [:]))
        var stack: [HTMLNode] = [root]

        let scalars = Array(html)
        var i = 0
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            stack.last?.append(HTMLNode(kind: .text(textBuffer)))
            textBuffer = ""
        }

        while i < scalars.count {
            if scalars[i] != "<" {
                textBuffer.append(scalars[i])
                i += 1
                continue
            }

            // Comentario / doctype: saltar entero.
            if matches(scalars, at: i, "<!--") {
                flushText()
                i = indexAfter(scalars, from: i, terminator: "-->") ?? scalars.count
                continue
            }
            if matches(scalars, at: i, "<!") {
                flushText()
                i = (indexAfter(scalars, from: i, terminator: ">")) ?? scalars.count
                continue
            }

            // Cierre.
            if matches(scalars, at: i, "</") {
                flushText()
                guard let end = indexOf(scalars, from: i, char: ">") else { break }
                let name = String(scalars[(i + 2)..<end])
                    .trimmingCharacters(in: .whitespaces).lowercased()
                // Cerrar hasta el tag correspondiente; tolera cierres faltantes.
                if let depth = stack.lastIndex(where: { $0.tag == name }), depth > 0 {
                    stack.removeSubrange(depth...)
                }
                i = end + 1
                continue
            }

            // Apertura.
            guard let end = tagEnd(scalars, from: i) else {
                textBuffer.append(scalars[i])
                i += 1
                continue
            }
            flushText()

            let raw = String(scalars[(i + 1)..<end])
            let selfClosing = raw.hasSuffix("/")
            let (name, attrs) = parseTag(raw)
            let node = HTMLNode(kind: .element(tag: name, attributes: attrs))
            stack.last?.append(node)

            // `<script>` y `<style>` tienen contenido crudo: saltarlo entero,
            // si no cualquier `<` adentro rompe el árbol.
            if name == "script" || name == "style" {
                if let close = indexAfter(scalars, from: end, terminator: "</\(name)") {
                    i = (indexAfter(scalars, from: close, terminator: ">")) ?? scalars.count
                } else {
                    i = scalars.count
                }
                continue
            }

            if !selfClosing && !voidTags.contains(name) {
                stack.append(node)
            }
            i = end + 1
        }

        flushText()
        return root
    }

    // MARK: Helpers de escaneo

    /// Fin del tag, saltando `>` que estén dentro de valores entrecomillados.
    private static func tagEnd(_ s: [Character], from start: Int) -> Int? {
        var i = start + 1
        var quote: Character? = nil
        while i < s.count {
            let c = s[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == ">" {
                return i
            }
            i += 1
        }
        return nil
    }

    private static func indexOf(_ s: [Character], from: Int, char: Character) -> Int? {
        var i = from
        while i < s.count {
            if s[i] == char { return i }
            i += 1
        }
        return nil
    }

    private static func matches(_ s: [Character], at: Int, _ needle: String) -> Bool {
        let n = Array(needle)
        guard at + n.count <= s.count else { return false }
        for k in 0..<n.count where s[at + k] != n[k] { return false }
        return true
    }

    /// Índice justo después de la primera aparición de `terminator`.
    private static func indexAfter(_ s: [Character], from: Int, terminator: String) -> Int? {
        let n = Array(terminator.lowercased())
        guard !n.isEmpty else { return nil }
        var i = from
        while i + n.count <= s.count {
            var hit = true
            for k in 0..<n.count where Character(s[i + k].lowercased()) != n[k] {
                hit = false
                break
            }
            if hit { return i + n.count }
            i += 1
        }
        return nil
    }

    /// Separa `div class="a b" id='x' hidden` en nombre + atributos.
    private static func parseTag(_ raw: String) -> (String, [String: String]) {
        let chars = Array(raw)
        var i = 0

        func skipSpaces() {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
        }

        skipSpaces()
        var name = ""
        while i < chars.count, !chars[i].isWhitespace, chars[i] != "/" {
            name.append(chars[i]); i += 1
        }

        var attrs: [String: String] = [:]
        while i < chars.count {
            skipSpaces()
            if i >= chars.count || chars[i] == "/" { break }

            var key = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "=", chars[i] != "/" {
                key.append(chars[i]); i += 1
            }
            if key.isEmpty { i += 1; continue }

            skipSpaces()
            var value = ""
            if i < chars.count, chars[i] == "=" {
                i += 1
                skipSpaces()
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let q = chars[i]; i += 1
                    while i < chars.count, chars[i] != q { value.append(chars[i]); i += 1 }
                    if i < chars.count { i += 1 }
                } else {
                    while i < chars.count, !chars[i].isWhitespace, chars[i] != ">" {
                        value.append(chars[i]); i += 1
                    }
                }
            } else {
                // Atributo booleano (`checked`, `disabled`, `selected`).
                value = key
            }
            attrs[key.lowercased()] = HTMLClean.decode(value)
        }

        return (name.lowercased(), attrs)
    }
}
