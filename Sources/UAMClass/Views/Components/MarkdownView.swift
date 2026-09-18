import SwiftUI

/// Markdown legible, no un volcado de texto plano.
///
/// No es un renderizador completo a propósito: cubre lo que Claude produce de
/// verdad — encabezados, viñetas, numeradas, citas, reglas, tablas, subtítulos
/// en negrita y énfasis inline — y para el resto cae a texto. Traer una
/// dependencia entera para eso sería desmedido, y el texto plano con
/// `**asteriscos**` o `| tabla | así |` a la vista se lee mal.
struct MarkdownView: View {
    let text: String
    var maxWidth: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: Bloques

    private enum Block {
        case heading(String, Int)
        case bullet(String)
        case numbered(String, String)
        case quote(String)
        case rule
        case code(String)
        case table([String], [[String]])
        case subheading(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var inCode = false
        var codeBuffer: [String] = []

        let lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    out.append(.code(codeBuffer.joined(separator: "\n")))
                    codeBuffer = []
                }
                inCode.toggle()
                i += 1
                continue
            }
            if inCode { codeBuffer.append(raw); i += 1; continue }

            if line.isEmpty { i += 1; continue }

            // Tabla: una fila de encabezado seguida de una fila separadora
            // `|---|---|`. Sin esto, Claude manda tablas y el usuario ve
            // texto con barras verticales sueltas — el motivo de este bloque.
            let headerCandidate = splitTableRow(line)
            if line.contains("|"), headerCandidate.count > 1, i + 1 < lines.count,
               isTableSeparator(lines[i + 1], columns: headerCandidate.count) {
                let headers = headerCandidate
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count {
                    let rowLine = lines[j].trimmingCharacters(in: .whitespaces)
                    guard rowLine.contains("|") else { break }
                    rows.append(splitTableRow(rowLine))
                    j += 1
                }
                out.append(.table(headers, rows))
                i = j
                continue
            }

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                out.append(.heading(String(line.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces), level))
            } else if line == "---" || line == "***" || line == "___" {
                out.append(.rule)
            } else if line.hasPrefix("> ") {
                out.append(.quote(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."),
                      line.distance(from: line.startIndex, to: dot) <= 2,
                      Int(line[line.startIndex..<dot]) != nil {
                out.append(.numbered(String(line[line.startIndex..<dot]),
                                     String(line[line.index(after: dot)...])
                                        .trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4,
                      !line.dropFirst(2).dropLast(2).contains("**") {
                // Línea entera en negrita: Claude la usa como subtítulo
                // suelto (sin `##`). La tratamos como tal en vez de como un
                // párrafo más, para que la jerarquía se note.
                out.append(.subheading(String(line.dropFirst(2).dropLast(2))))
            } else {
                out.append(.paragraph(line))
            }
            i += 1
        }
        if inCode, !codeBuffer.isEmpty {
            out.append(.code(codeBuffer.joined(separator: "\n")))
        }
        return out
    }

    private func isTableSeparator(_ raw: String, columns: Int) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.contains("-") else { return false }
        let allowed = CharacterSet(charactersIn: "-:| ")
        guard s.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        let cells = splitTableRow(s)
        guard cells.count == columns else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
        }
    }

    private func splitTableRow(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @ViewBuilder
    private func row(_ block: Block) -> some View {
        switch block {
        case .heading(let t, let level):
            Text(inline(t))
                .font(.system(size: level <= 1 ? 20 : (level == 2 ? 16 : 14),
                              weight: level <= 2 ? .bold : .semibold,
                              design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, level <= 2 ? 8 : 4)

        case .bullet(let t):
            HStack(alignment: .top, spacing: 7) {
                Circle().fill(Palette.accent.opacity(0.55))
                    .frame(width: 4, height: 4).padding(.top, 6)
                Text(inline(t)).font(Type.body).foregroundStyle(Palette.textSecondary)
            }

        case .numbered(let n, let t):
            HStack(alignment: .top, spacing: 7) {
                Text(n + ".")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(inline(t)).font(Type.body).foregroundStyle(Palette.textSecondary)
            }

        case .quote(let t):
            HStack(alignment: .top, spacing: 8) {
                Capsule().fill(Palette.accent.opacity(0.4)).frame(width: 3)
                Text(inline(t)).font(Type.body).foregroundStyle(Palette.textTertiary)
            }
            .padding(.vertical, 2)

        case .subheading(let t):
            Text(inline(t))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 6)

        case .rule:
            Divider().overlay(Palette.divider).padding(.vertical, 4)

        case .table(let headers, let rows):
            table(headers: headers, rows: rows)

        case .code(let t):
            Text(t)
                .font(Type.mono)
                .foregroundStyle(Palette.textPrimary)
                .padding(Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.textPrimary.opacity(0.05)))

        case .paragraph(let t):
            Text(inline(t))
                .font(Type.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func table(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                    Text(inline(cell))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider().overlay(Palette.divider).gridCellColumns(headers.count)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                GridRow {
                    ForEach(Array(headers.indices), id: \.self) { col in
                        Text(inline(col < cells.count ? cells[col] : ""))
                            .font(Type.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.textPrimary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
        .padding(.vertical, 2)
    }

    /// Énfasis inline por `AttributedString`, que ya entiende `**` y `*`.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
    }
}
