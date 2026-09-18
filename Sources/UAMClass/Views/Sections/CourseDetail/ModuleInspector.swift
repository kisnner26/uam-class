import SwiftUI
import UniformTypeIdentifiers

/// Inspector modal (sheet) para ver el contenido de un módulo Moodle.
struct ModuleInspector: View {
    let module: MoodleModule
    let course: MoodleCourse
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { CourseAccent.color(for: course) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)
            body_
                #if os(macOS)
                .frame(minWidth: 560, minHeight: 380)
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 500)
        #endif
        .background(AmbientBackdrop(tint: accent, intensity: 0.5))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            IconTile(symbol: symbol(for: module.modname), tint: accent, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel(for: module.modname))
                    .labelCaps()
                Text(module.displayName)
                    .font(Type.subtitle)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !module.cleanDescription.isEmpty {
                    Text(module.cleanDescription)
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: Space.xs)

            GlassIconButton(symbol: "xmark", help: "Cerrar", size: 24) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Space.md)
        .background(.thinMaterial)
    }

    @ViewBuilder private var body_: some View {
        switch module.modname {
        case "resource", "folder":
            ResourceInspector(module: module, course: course)
        case "url":
            URLInspector(module: module)
        case "forum":
            ForumInspector(module: module)
        case "assign":
            AssignmentInspector(module: module, course: course)
        #if os(macOS)
        case "quiz":
            QuizInspector(module: module, course: course)
        #endif
        case "choice":
            ChoiceInspector(module: module, course: course)
        case "choicegroup", "groupselect":
            ChoiceGroupInspector(module: module, course: course)
        case "feedback", "survey":
            FeedbackInspector(module: module, course: course)
        default:
            GenericInspector(module: module)
        }
    }

    private func symbol(for modname: String) -> String {
        switch modname {
        case "choice":            return "checklist"
        case "choicegroup", "groupselect": return "person.3.sequence.fill"
        case "feedback", "survey": return "list.clipboard"
        case "assign":    return "square.and.pencil"
        case "resource":  return "doc"
        case "url":       return "link"
        case "forum":     return "bubble.left.and.bubble.right"
        case "quiz":      return "checkmark.square"
        case "folder":    return "folder"
        case "page":      return "doc.text"
        case "book":      return "book"
        case "label":     return "text.alignleft"
        case "lesson":    return "list.bullet.rectangle"
        case "chat":      return "message"
        default:          return "circle.dashed"
        }
    }

    private func kindLabel(for modname: String) -> String {
        switch modname {
        case "choice":            return "Consulta"
        case "choicegroup", "groupselect": return "Elección de grupo"
        case "feedback", "survey": return "Encuesta"
        case "assign":    return "Tarea"
        case "resource":  return "Recurso"
        case "url":       return "Enlace"
        case "forum":     return "Foro"
        case "quiz":      return "Cuestionario"
        case "folder":    return "Carpeta"
        case "page":      return "Página"
        case "book":      return "Libro"
        case "lesson":    return "Lección"
        case "chat":      return "Chat"
        default:          return modname.capitalized
        }
    }
}

// MARK: - Resource / Folder

private struct ResourceInspector: View {
    let module: MoodleModule
    let course: MoodleCourse
    @StateObject private var downloads = DownloadService.shared
    @EnvironmentObject var state: AppState
    @State private var selectedFile: MoodleContentFile?
    @State private var tokenizedURL: URL?
    @State private var showAISummary: Bool = false

    var body: some View {
        let files = (module.contents ?? []).filter { ($0.type ?? "file") == "file" }
        Group {
            if files.isEmpty {
                fallbackNoFiles
            } else {
                #if os(macOS)
                HSplitView {
                    fileList(files)
                        .frame(minWidth: 220, idealWidth: 260)
                    previewPane
                        .frame(minWidth: 360)
                }
                #else
                // Sin split view en iPhone: la lista arriba (compacta) y la
                // previsualización del archivo elegido debajo, en una sola
                // pantalla que se desplaza.
                VStack(spacing: 0) {
                    fileList(files)
                        .frame(maxHeight: files.count > 1 ? 180 : 90)
                    Divider()
                    previewPane
                        .frame(minHeight: 320)
                }
                #endif
            }
        }
        .task {
            await downloads.setToken(state.moodle.currentToken)
            if selectedFile == nil, let first = files.first {
                selectFile(first)
            }
        }
    }

    private func fileList(_ files: [MoodleContentFile]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { i, file in
                    Button {
                        selectFile(file)
                    } label: {
                        FileSidebarRow(file: file,
                                       selected: selectedFile?.id == file.id,
                                       isLast: i == files.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Palette.surface)
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                previewToolbar(file)
                Divider().background(Palette.divider)
                if showAISummary && file.isPDF, let url = tokenizedURL {
                    PDFSummaryPanel(url: url)
                } else {
                    InlinePreview(file: file, tokenizedURL: tokenizedURL)
                }
            } else {
                EmptyState(icon: "doc",
                           title: "Selecciona un archivo",
                           subtitle: nil)
            }
        }
    }

    private func previewToolbar(_ file: MoodleContentFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
            Text(file.displayName)
                .font(Type.bodyBold)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            if !file.displaySize.isEmpty {
                Text(file.displaySize)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            actionsBar(file)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .background(Palette.surface)
    }

    private func actionsBar(_ file: MoodleContentFile) -> some View {
        let s = downloads.progress[file.id] ?? .idle
        let existing = downloads.existingLocal(for: file, in: course)
        return HStack(spacing: 4) {
            if file.isPDF {
                Button {
                    showAISummary.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAISummary ? "sparkles" : "sparkle")
                            .font(.system(size: 11, weight: .medium))
                        Text(showAISummary ? "Preview" : "Resumen")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(showAISummary ? .white : Palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(showAISummary ? Palette.accent : Palette.accentSoft))
                }
                .buttonStyle(.plain)
                .help("Resumen automático (local, sin conexión)")
            }
            if case .downloading = s {
                ProgressView().controlSize(.small)
            } else if case .done(let url) = s {
                #if os(macOS)
                miniAction("magnifyingglass", "Quick Look") { downloads.quickLook(url) }
                miniAction("folder", "Mostrar en Finder") { downloads.revealInFinder(url) }
                miniAction("arrow.up.forward.app", "Abrir con app externa") { downloads.openWithDefaultApp(url) }
                #else
                miniAction("checkmark.circle", "Descargado") {}
                #endif
            } else if let url = existing {
                #if os(macOS)
                miniAction("magnifyingglass", "Quick Look") { downloads.quickLook(url) }
                miniAction("folder", "Mostrar en Finder") { downloads.revealInFinder(url) }
                #else
                miniAction("checkmark.circle", "Descargado") {}
                #endif
            } else {
                miniAction("arrow.down.circle", "Guardar copia") {
                    Task { await downloads.download(file, for: course) }
                }
            }
        }
    }

    private func miniAction(_ symbol: String, _ tooltip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.surfaceHover))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func selectFile(_ file: MoodleContentFile) {
        selectedFile = file
        Task {
            if let s = file.fileurl {
                self.tokenizedURL = await state.moodle.tokenizedURL(from: s)
            }
        }
    }

    private var fallbackNoFiles: some View {
        VStack(spacing: Space.md) {
            EmptyState(
                icon: "arrow.up.right.square",
                title: "El servidor no expone archivos por API",
                subtitle: "Moodle no listó archivos para este recurso. Se abre directo en el navegador."
            )
            if let s = module.url, let u = URL(string: s) {
                PrimaryButton(title: "Abrir en Moodle web", loading: false, disabled: false) {
                    PlatformBridge.openURL(u)
                }
                .padding(.horizontal, Space.md)
            }
        }
        .padding(.top, Space.lg)
    }
}

private struct FileSidebarRow: View {
    let file: MoodleContentFile
    let selected: Bool
    let isLast: Bool
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Palette.accent : Palette.textSecondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.displayName)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if !file.displaySize.isEmpty {
                        Text(file.displaySize)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                if selected {
                    Rectangle().fill(Palette.accent).frame(width: 2, height: 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Palette.accentSoft.opacity(0.7)
                                   : (hovered ? Palette.surfaceHover : Color.clear))
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)

            if !isLast { Divider().background(Palette.divider).padding(.horizontal, 8) }
        }
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }

    private var symbol: String {
        if file.isPDF { return "doc.richtext" }
        if file.isImage { return "photo" }
        if file.isVideo { return "play.rectangle" }
        return "doc"
    }
}

private struct FileRow: View {
    let file: MoodleContentFile
    let course: MoodleCourse
    let isLast: Bool
    @ObservedObject private var downloads = DownloadService.shared
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Palette.background)
                    Image(systemName: symbolFor(file))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.displayName)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if !file.displaySize.isEmpty {
                            Text(file.displaySize).font(Type.caption).foregroundStyle(Palette.textTertiary)
                        }
                        if let mime = file.mimetype {
                            Text(mime).font(Type.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        }
                    }
                }

                Spacer()

                actionButtons
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(hovered ? Palette.surfaceHover : Color.clear)

            if !isLast { Divider().background(Palette.divider) }
        }
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }

    @ViewBuilder private var actionButtons: some View {
        let state = downloads.progress[file.id] ?? .idle
        let existing = downloads.existingLocal(for: file, in: course)

        switch state {
        case .downloading:
            ProgressView().controlSize(.small)
        case .done(let url):
            #if os(macOS)
            HStack(spacing: 6) {
                iconButton("eye", "Vista previa") { downloads.quickLook(url) }
                iconButton("folder", "Mostrar en Finder") { downloads.revealInFinder(url) }
                iconButton("arrow.up.forward.app", "Abrir con app externa") { downloads.openWithDefaultApp(url) }
            }
            #else
            let _ = url
            iconButton("checkmark.circle", "Descargado") {}
            #endif
        case .failed(let msg):
            Text(msg).font(Type.caption).foregroundStyle(Palette.danger).lineLimit(1)
            iconButton("arrow.clockwise", "Reintentar") {
                Task { await downloads.download(file, for: course) }
            }
        case .idle:
            if let url = existing {
                #if os(macOS)
                HStack(spacing: 6) {
                    iconButton("eye", "Vista previa") { downloads.quickLook(url) }
                    iconButton("folder", "Mostrar en Finder") { downloads.revealInFinder(url) }
                }
                #else
                let _ = url
                iconButton("checkmark.circle", "Descargado") {}
                #endif
            } else {
                Button {
                    Task { await downloads.download(file, for: course) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 12))
                        Text("Descargar").font(Type.caption)
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5).fill(Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconButton(_ symbol: String, _ tooltip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func symbolFor(_ file: MoodleContentFile) -> String {
        if file.isPDF { return "doc.richtext" }
        if file.isImage { return "photo" }
        if file.isVideo { return "play.rectangle" }
        let ext = (file.filename as NSString?)?.pathExtension.lowercased() ?? ""
        switch ext {
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "zip", "rar", "7z": return "archivebox"
        case "mp3", "wav", "m4a": return "waveform"
        default: return "doc"
        }
    }
}

// MARK: - URL (enlace)

private struct URLInspector: View {
    let module: MoodleModule
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            let targetURL: URL? = {
                if let u = module.url, let url = URL(string: u) { return url }
                if let first = module.contents?.first?.fileurl, let url = URL(string: first) { return url }
                return nil
            }()

            if let url = targetURL {
                HStack(spacing: Space.sm) {
                    Image(systemName: "link").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    Text(url.absoluteString)
                        .font(Type.mono)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(Space.md)
                .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border, lineWidth: 0.5))

                PrimaryButton(title: "Abrir en el navegador", loading: false, disabled: false) {
                    PlatformBridge.openURL(url)
                }
            } else {
                EmptyState(icon: "link", title: "Sin URL", subtitle: nil)
            }
        }
        .padding(Space.md)
    }
}

// MARK: - Forum

private struct ForumInspector: View {
    let module: MoodleModule
    @EnvironmentObject var state: AppState

    @State private var forum: MoodleForum?
    @State private var discussions: [MoodleForumDiscussion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selectedDiscussion: MoodleForumDiscussion?

    var body: some View {
        Group {
            if let d = selectedDiscussion {
                DiscussionView(discussion: d, back: { selectedDiscussion = nil })
            } else {
                discussionsList
            }
        }
        .task { await load() }
    }

    private var discussionsList: some View {
        ScrollView {
            if loading && discussions.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Cargando foro…").font(Type.caption).foregroundStyle(Palette.textSecondary)
                }
                .padding(Space.md)
            } else if let err = error {
                Text(err).font(Type.caption).foregroundStyle(Palette.danger).padding(Space.md)
            } else if discussions.isEmpty {
                EmptyState(icon: "bubble.left.and.bubble.right", title: "Sin discusiones", subtitle: nil)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(discussions.enumerated()), id: \.element.id) { i, d in
                        Button {
                            selectedDiscussion = d
                        } label: {
                            DiscussionRow(discussion: d, isLast: i == discussions.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.border, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .padding(Space.md)
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let forums = try await state.moodle.forumsByCourse(courseId: module.instance ?? 0)
            let f = forums.first(where: { $0.cmid == module.id })
                ?? forums.first(where: { $0.name == module.name })
                ?? forums.first
            guard let forum = f else {
                self.error = "Foro no encontrado."; return
            }
            self.forum = forum
            let r = try await state.moodle.discussions(forumId: forum.id)
            self.discussions = r.discussions
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DiscussionRow: View {
    let discussion: MoodleForumDiscussion
    let isLast: Bool
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(discussion.name)
                        .font(Type.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let name = discussion.userfullname {
                            Text(name).font(Type.caption).foregroundStyle(Palette.textSecondary)
                        }
                        if let when = discussion.when {
                            Text("·").font(Type.caption).foregroundStyle(Palette.textTertiary)
                            Text(when, style: .relative)
                                .font(Type.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
                Spacer()
                if let n = discussion.numreplies, n > 0 {
                    Text("\(n)")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.background))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(hovered ? Palette.surfaceHover : Color.clear)
            if !isLast { Divider().background(Palette.divider) }
        }
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

private struct DiscussionView: View {
    let discussion: MoodleForumDiscussion
    let back: () -> Void

    @EnvironmentObject var state: AppState
    @State private var posts: [MoodleForumPost] = []
    @State private var loading = false
    @State private var error: String?
    @State private var replyText = ""
    @State private var replyingToPost: MoodleForumPost?
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Discusiones").font(Type.caption)
                    }
                    .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(Space.sm)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(discussion.name).font(Type.title).foregroundStyle(Palette.textPrimary)
                    if loading && posts.isEmpty {
                        ProgressView().controlSize(.small)
                    } else if let err = error {
                        Text(err).font(Type.caption).foregroundStyle(Palette.danger)
                    } else {
                        ForEach(posts) { post in
                            PostCard(post: post) {
                                replyingToPost = post
                            }
                        }
                    }
                }
                .padding(Space.md)
            }

            if let replyingTo = replyingToPost {
                replyBar(replyingTo: replyingTo)
            }
        }
        .task { await load() }
    }

    private func replyBar(replyingTo: MoodleForumPost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Respondiendo a \(replyingTo.author?.fullname ?? "…")")
                    .labelCaps()
                Spacer()
                Button {
                    replyingToPost = nil; replyText = ""
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 8) {
                TextEditor(text: $replyText)
                    .font(Type.body)
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border, lineWidth: 0.5))
                Button {
                    Task { await sendReply(to: replyingTo) }
                } label: {
                    if sending { ProgressView().controlSize(.small) }
                    else { Text("Enviar").font(Type.bodyBold).foregroundStyle(Palette.textOnAccent) }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accent))
                .disabled(replyText.isEmpty || sending)
            }
        }
        .padding(Space.md)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: 0.5) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let r = try await state.moodle.posts(discussionId: discussion.discussionId)
            self.posts = r.posts
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendReply(to post: MoodleForumPost) async {
        sending = true; defer { sending = false }
        do {
            _ = try await state.moodle.addForumPost(postId: post.id,
                                                    subject: "Re: " + (post.cleanSubject.isEmpty ? discussion.name : post.cleanSubject),
                                                    message: replyText)
            replyText = ""
            replyingToPost = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PostCard: View {
    let post: MoodleForumPost
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Avatar(url: post.author?.urls?.profileimage,
                       name: post.author?.fullname ?? "?", size: 22,
                       userID: post.author?.id)
                Text(post.author?.fullname ?? "Anónimo").font(Type.bodyBold).foregroundStyle(Palette.textPrimary)
                if let when = post.when {
                    Text("·").font(Type.caption).foregroundStyle(Palette.textTertiary)
                    Text(when, style: .relative).font(Type.caption).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Button(action: onReply) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10))
                        Text("Responder").font(Type.caption)
                    }
                    .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Text(post.cleanMessage)
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.md)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.border, lineWidth: 0.5))
    }
}

// MARK: - Assignment

private struct AssignmentInspector: View {
    let module: MoodleModule
    let course: MoodleCourse

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var status: MoodleAssignSubmissionStatus?
    @State private var loading = false
    @State private var error: String?
    @State private var busy: String?
    @State private var justUploaded: String?
    @State private var showFileImporter = false

    private var attempt: MoodleAssignLastAttempt? { status?.lastattempt }
    private var submission: MoodleAssignSubmission? { attempt?.submission }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if !module.cleanDescription.isEmpty {
                    Card {
                        Text(module.cleanDescription)
                            .font(Type.body)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let due = module.dates?.compactMap(\.date).first {
                    Card {
                        HStack {
                            Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                            Text("Entrega")
                                .labelCaps()
                            Spacer()
                            Text(due.formatted(date: .complete, time: .shortened))
                                .font(Type.body)
                                .foregroundStyle(due < Date() ? Palette.danger : Palette.textPrimary)
                        }
                    }
                }
                if loading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Consultando estado…").font(Type.caption).foregroundStyle(Palette.textSecondary)
                    }
                } else if let s = status?.lastattempt {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tu entrega").labelCaps()
                            InfoLine(label: "Estado",  value: friendlyStatus(s.submission?.status))
                            InfoLine(label: "Calificación",  value: HTMLClean.plain(s.feedback?.gradefordisplay))
                            InfoLine(label: "Última modificación", value: date(s.submission?.timemodified))
                            InfoLine(label: "Puede editar", value: (s.canedit == true) ? "Sí" : "No")
                        }
                    }
                }
                if let err = error {
                    Text(err).font(Type.caption).foregroundStyle(Palette.danger)
                }

                let files = submission?.files ?? []
                if !files.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Archivos entregados").labelCaps()
                            ForEach(files) { f in
                                HStack(spacing: Space.xs) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.textTertiary)
                                    Text(f.displayName)
                                        .font(Type.caption)
                                        .foregroundStyle(Palette.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    if let s = f.sizeText {
                                        Text(s)
                                            .font(Type.micro)
                                            .foregroundStyle(Palette.textQuaternary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Envío de archivos").labelCaps()

                        if let justUploaded {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.success)
                                    .font(.system(size: 11))
                                Text("“\(justUploaded)” quedó adjunto como borrador.")
                                    .font(Type.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }

                        HStack(spacing: Space.xs) {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label(busy == nil ? "Elegir archivo…" : busy!,
                                      systemImage: "arrow.up.doc")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .nativeGlassButton()
                            .controlSize(.regular)
                            .disabled(busy != nil || attempt?.submissionsenabled == false)
                            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
                                if case .success(let url) = result {
                                    Task { await upload(fileURL: url) }
                                }
                            }

                            Button {
                                Task { await submit() }
                            } label: {
                                Label("Enviar para calificar", systemImage: "paperplane.fill")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .nativeGlassButton(prominent: true)
                            .tint(prefs.tint)
                            .controlSize(.regular)
                            .disabled(busy != nil || submission?.isSubmitted == true
                                      || (submission?.files.isEmpty ?? true) && justUploaded == nil)

                            if busy != nil { ProgressView().controlSize(.small) }
                            Spacer(minLength: 0)
                        }

                        Text("Adjuntar deja la tarea en borrador. Recién “Enviar para calificar” se la muestra al docente.")
                            .font(Type.micro)
                            .foregroundStyle(Palette.textQuaternary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Space.md)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            status = try await state.moodle.submissionStatus(assignId: module.instance ?? 0)
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func upload(fileURL url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        error = nil
        busy = "Subiendo…"
        defer { busy = nil }

        do {
            let itemId = try await state.moodle.uploadDraft(fileURL: url)
            busy = "Adjuntando…"
            try await state.moodle.saveSubmission(assignId: module.instance ?? 0,
                                                  draftItemId: itemId)
            justUploaded = url.lastPathComponent
            await load()
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func submit() async {
        error = nil
        busy = "Enviando…"
        defer { busy = nil }
        do {
            try await state.moodle.submitForGrading(assignId: module.instance ?? 0)
            justUploaded = nil
            await load()
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func friendlyStatus(_ s: String?) -> String {
        switch s {
        case "submitted":     return "Enviada"
        case "new", "draft":  return "Borrador / sin enviar"
        case nil:             return "—"
        default:              return s ?? "—"
        }
    }

    private func date(_ ts: Int?) -> String {
        guard let t = ts, t > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(t))
            .formatted(date: .abbreviated, time: .shortened)
    }
}

private struct InfoLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(Type.caption).foregroundStyle(Palette.textSecondary).frame(width: 140, alignment: .leading)
            Text(value.isEmpty ? "—" : value).font(Type.body).foregroundStyle(Palette.textPrimary)
            Spacer()
        }
    }
}

// MARK: - Generic (fallback)

private struct GenericInspector: View {
    let module: MoodleModule
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if !module.cleanDescription.isEmpty {
                    Card {
                        Text(module.cleanDescription).font(Type.body).foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    EmptyState(icon: "circle.dashed",
                               title: "Sin vista específica",
                               subtitle: "Este tipo de módulo (\(module.modname)) todavía no tiene inspector propio. Abrilo en Moodle web.")
                }
                if let url = module.url, let u = URL(string: url) {
                    PrimaryButton(title: "Abrir en Moodle web", loading: false, disabled: false) {
                        MoodleOpener.shared.open(u, state: state)
                    }
                }
            }
            .padding(Space.md)
        }
    }
}
