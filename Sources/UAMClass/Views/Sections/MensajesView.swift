import SwiftUI

/// Sección "Mensajes" con lista de conversaciones a la izquierda y chat a la derecha.
struct MensajesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var conversations: [MoodleConversation] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: MoodleConversation?
    @State private var showNewChat = false

    var body: some View {
        Group {
            #if os(macOS)
            HSplitView {
                conversationsPane
                    .frame(minWidth: 260, idealWidth: 300)
                chatPane
                    .frame(minWidth: 380)
            }
            #else
            // Sin split view en iPhone: la lista empuja el chat sobre el
            // NavigationStack de la pestaña (RootTabView ya provee uno).
            conversationsPane
                .navigationDestination(item: $selected) { c in
                    ChatView(conversation: c) { newConv in
                        if let idx = conversations.firstIndex(where: { $0.id == newConv.id }) {
                            conversations[idx] = newConv
                        }
                    }
                    .environmentObject(state)
                }
            #endif
        }
        .task { await load() }
        .sheet(isPresented: $showNewChat) {
            NewChatSheet(onOpenConversation: { convId in
                showNewChat = false
                Task { await refreshAndSelect(convId) }
            })
            .environmentObject(state).environmentObject(prefs)
        }
    }

    // MARK: List

    private var conversationsPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Chats")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                if !conversations.isEmpty {
                    CountBadge(conversations.count)
                }
                Spacer()
                GlassIconButton(symbol: "square.and.pencil", help: "Nuevo chat", size: 26) {
                    showNewChat = true
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 10)

            Divider().overlay(Palette.divider)

            ScrollView {
                if loading && conversations.isEmpty {
                    VStack(spacing: Space.xs) {
                        ForEach(0..<5, id: \.self) { _ in SkeletonRow() }
                    }
                    .padding(.top, Space.xs)
                } else if conversations.isEmpty {
                    EmptyState(icon: "bubble.left.and.bubble.right",
                               title: "Sin chats",
                               subtitle: "Empezá una conversación con el botón de arriba.")
                        .frame(minHeight: 240)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(conversations) { c in
                            Button {
                                withAnimation(Motion.quick) { selected = c }
                                Task { await markRead(c) }
                            } label: {
                                ConversationRow(conversation: c,
                                                selected: selected?.id == c.id,
                                                tint: prefs.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(.thinMaterial)
    }

    // MARK: Chat pane

    private var chatPane: some View {
        Group {
            if let c = selected {
                ChatView(conversation: c) { newConv in
                    // actualizar la conversación en la lista con último mensaje
                    if let idx = conversations.firstIndex(where: { $0.id == newConv.id }) {
                        conversations[idx] = newConv
                    }
                }
                .environmentObject(state)
                .id(c.id)
            } else {
                EmptyState(icon: "bubble.left.and.bubble.right",
                           title: "Elegí un chat",
                           subtitle: "Selecciona una conversación a la izquierda.")
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let uid = state.moodleSiteInfo?.userid else { return }
        loading = true; defer { loading = false }
        do {
            conversations = try await state.moodle.conversations(userId: uid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshAndSelect(_ convId: Int) async {
        await load()
        selected = conversations.first { $0.id == convId }
    }

    private func markRead(_ conv: MoodleConversation) async {
        // Sin API oficial silenciosa; simplemente refrescamos al abrir.
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    let conversation: MoodleConversation
    let selected: Bool
    var tint: Color = Palette.accent
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: conversation.members?.first?.profileimageurl,
                   name: conversation.displayName, size: 34, accent: selected,
                   userID: conversation.members?.first?.id)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let n = conversation.unreadcount, n > 0 {
                        Text("\(n)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(tint))
                            .shadow(color: tint.opacity(0.45), radius: 4, x: 0, y: 1)
                    }
                    Spacer()
                    if let d = conversation.lastMessage?.when {
                        Text(d, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                if let last = conversation.lastMessage {
                    Text(last.clean)
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(selected ? tint.opacity(0.14)
                               : Palette.textPrimary.opacity(hovered ? 0.05 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(tint.opacity(selected ? 0.24 : 0), lineWidth: 0.5)
                )
        }
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// MARK: - Chat view

struct ChatView: View {
    let conversation: MoodleConversation
    let onUpdate: (MoodleConversation) -> Void

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var messages: [MoodleMessage] = []
    @State private var loading = false
    @State private var input: String = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            messagesList
            Divider().background(Palette.divider)
            composer
        }
        .task { await loadMessages() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(url: conversation.members?.first?.profileimageurl,
                   name: conversation.displayName, size: 32, accent: true,
                   userID: conversation.members?.first?.id)
                .shadow(color: prefs.tint.opacity(0.3), radius: 6, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                if let n = conversation.membercount, n > 1 {
                    Text("\(n) miembros")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var messagesList: some View {
        ScrollViewReader { scroll in
            ScrollView {
                if loading && messages.isEmpty {
                    ProgressView().controlSize(.small).padding()
                } else if let err = error {
                    Text(err).font(Type.caption).foregroundStyle(Palette.danger).padding()
                } else if messages.isEmpty {
                    EmptyState(icon: "text.bubble",
                               title: "Sin mensajes",
                               subtitle: "Sé el primero en escribir.")
                        .frame(minHeight: 240)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(messages) { m in
                            MessageBubble(
                                message: m,
                                mine: m.useridfrom == (state.moodleSiteInfo?.userid ?? 0),
                                senderName: senderName(for: m),
                                tint: prefs.tint
                            )
                            .id(m.id)
                        }
                    }
                    .padding(Space.md)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.4))
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { scroll.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Escribí un mensaje…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Type.body)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassBar(radius: Radius.lg)
                .onSubmit(send)

            let empty = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending
            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background {
                        Circle().fill(prefs.tint.brandGradient).opacity(empty ? 0.35 : 1)
                    }
                    .overlay(Circle().strokeBorder(Palette.rimOnDark, lineWidth: 0.6))
                    .shadow(color: prefs.tint.opacity(empty ? 0 : 0.4), radius: 8, x: 0, y: 3)
                    .scaleEffect(empty ? 0.94 : 1)
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .keyboardShortcut(.return, modifiers: [.command])
            .animation(Motion.quick, value: empty)
        }
        .padding(Space.sm)
        .background(.thinMaterial)
    }

    private func senderName(for m: MoodleMessage) -> String? {
        guard let member = conversation.members?.first(where: { $0.id == m.useridfrom }) else {
            return nil
        }
        return Fmt.properName(member.fullname)
    }

    private func loadMessages() async {
        guard let uid = state.moodleSiteInfo?.userid else { return }
        loading = true; defer { loading = false }
        do {
            let r = try await state.moodle.conversationMessages(currentUserId: uid, convId: conversation.id)
            self.messages = r.messages
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        input = ""
        Task {
            defer { sending = false }
            do {
                let new = try await state.moodle.sendMessage(convId: conversation.id, text: text)
                self.messages.append(contentsOf: new)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: MoodleMessage
    let mine: Bool
    let senderName: String?
    var tint: Color = Palette.accent

    /// Esquina "pegada" del lado del emisor: el detalle que hace que las
    /// burbujas se lean como un chat y no como una lista de cajas.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: mine ? 14 : 4,
            bottomTrailingRadius: mine ? 4 : 14,
            topTrailingRadius: 14,
            style: .continuous
        )
    }

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 64) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if !mine, let name = senderName {
                    Text(name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 4)
                }

                Text(message.clean)
                    .font(Type.body)
                    .foregroundStyle(mine ? .white : Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if mine {
                            shape.fill(tint.brandGradient)
                        } else {
                            shape.fill(.regularMaterial)
                        }
                    }
                    .overlay(
                        shape.strokeBorder(mine ? Palette.rimOnDark : Palette.rim,
                                           lineWidth: 0.6)
                    )
                    .shadow(color: mine ? tint.opacity(0.25) : .black.opacity(0.05),
                            radius: 6, x: 0, y: 2)

                if let d = message.when {
                    Text(d, style: .time)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textQuaternary)
                        .padding(.horizontal, 4)
                }
            }
            if !mine { Spacer(minLength: 64) }
        }
    }
}

// MARK: - New chat sheet

private struct NewChatSheet: View {
    let onOpenConversation: (Int) -> Void

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var results: [MoodleSearchUser] = []
    @State private var searching = false
    @State private var sending: Int? = nil
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconTile(symbol: "square.and.pencil", tint: prefs.tint, size: 30, filled: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nuevo chat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Buscá a alguien y mandá el primer mensaje")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                GlassIconButton(symbol: "xmark", help: "Cerrar", size: 24) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Space.md)

            Divider().overlay(Palette.divider)

            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: 8) {
                    SearchField(text: $search, placeholder: "Buscar personas", width: 240)
                    if searching { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }

                if !results.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(results) { u in
                                userRow(u)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .adaptiveSurface(prefs, cornerRadius: Radius.md)
                } else if !search.isEmpty && !searching {
                    Text("Sin resultados. Probá con el nombre completo.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mensaje inicial").labelCaps()
                    TextEditor(text: $draft)
                        .font(Type.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 76)
                        .padding(7)
                        .adaptiveSurface(prefs, cornerRadius: Radius.md, elevation: .flat)
                }

                Spacer(minLength: 0)
            }
            .padding(Space.md)
        }
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
    }

    private func userRow(_ u: MoodleSearchUser) -> some View {
        HStack(spacing: 10) {
            Avatar(url: u.profileimageurl, name: u.fullname, size: 28, userID: u.id)

            Text(Fmt.properName(u.fullname))
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.xs)

            if sending == u.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Enviar") {
                    Task { await sendTo(u) }
                }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func runSearch() async {
        guard let uid = state.moodleSiteInfo?.userid,
              !search.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true; defer { searching = false }
        do {
            let r = try await state.moodle.searchUsers(currentUserId: uid, search: search)
            results = r.contacts + r.noncontacts
        } catch {
            // silencioso
        }
    }

    private func sendTo(_ u: MoodleSearchUser) async {
        sending = u.id
        defer { sending = nil }
        do {
            try await state.moodle.sendInstantMessage(toUserId: u.id, text: draft)
            // El endpoint no devuelve convId directamente. Cerramos el sheet;
            // el caller va a recargar la lista.
            onOpenConversation(0)
        } catch {
            // TODO: mostrar alerta
            onOpenConversation(0)
        }
    }
}
