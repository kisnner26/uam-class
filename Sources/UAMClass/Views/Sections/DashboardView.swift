import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @ObservedObject private var watcher = ChangeWatcher.shared
    @State private var upcoming: [UpcomingItem] = []
    @State private var loadingUpcoming = false

    // El menú de la consola: una barra de estado arriba, un aviso, y la GRILLA.
    // Sin tarjetas apiladas, sin columnas, sin métricas sueltas — todo lo que se
    // puede abrir es un mosaico del mismo tamaño, y nada más ocupa lugar.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                // Se respetan los interruptores de Configuración: cada widget
                // del sistema anterior mapea a una banda del menú.
                if shows(.hero)     { topBar }
                if shows(.upcoming) { noticeBar }
                if shows(.weekly)   { weekRail }
                if shows(.courses) || shows(.stats) { channelGrid }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task { await loadUpcoming() }
    }

    private func shows(_ id: DashboardWidgetID) -> Bool {
        prefs.dashboardWidgets.first { $0.id == id }?.visible ?? true
    }

    // MARK: Barra superior

    private var topBar: some View {
        let name = state.moodleSiteInfo?.fullname ?? ""
        let first = Fmt.properName(Fmt.firstWord(name))

        return HStack(alignment: .center, spacing: Space.sm) {
            if let account = AccountStore.shared.accounts.first(where: {
                $0.id == AccountStore.shared.activeID
            }), let mii = store.mii(for: account.id) {
                MiiView(mii: mii, size: 52)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: prefs.tint.opacity(0.25), radius: 8, y: 3)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(dateHeading.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Palette.textTertiary)
                HStack(spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(first)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(prefs.tint)
                }
            }

            Spacer(minLength: Space.sm)

            // Reloj: el menú de la consola siempre lo tiene, y acá además
            // ancla la sensación de "estoy en un sistema", no en una web.
            Text(Date(), style: .time)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        }
        .padding(.bottom, 2)
    }

    // MARK: Aviso
    //
    // Una franja ancha, no una tarjeta. Es el tablón del menú: una sola línea,
    // siempre en el mismo lugar, con lo único que hay que saber ya.

    private var noticeBar: some View {
        let text = focusLine ?? "Sin entregas pendientes. Buen momento para adelantar."
        let urgent = upcoming.first.map { $0.date.timeIntervalSinceNow < 86_400 * 2 } ?? false

        return HStack(spacing: 10) {
            Image(systemName: urgent ? "exclamationmark.circle.fill" : "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 11)
        .background(
            ZStack {
                LinearGradient(colors: urgent
                               ? [Palette.warning, Palette.warning.opacity(0.82)]
                               : [prefs.tint, prefs.tint.opacity(0.78)],
                               startPoint: .leading, endPoint: .trailing)
                Palette.specular.opacity(0.6)
            }
        )
        .clipShape(Capsule())
        .shadow(color: (urgent ? Palette.warning : prefs.tint).opacity(0.28),
                radius: 12, y: 4)
    }

    // MARK: Riel de la semana
    //
    // Siete cápsulas en fila. Reemplaza al calendario encajonado: ocupa un
    // tercio del alto y se lee de un vistazo.

    private var weekRail: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }

        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let count = upcoming.filter { cal.isDate($0.date, inSameDayAs: day) }.count

                VStack(spacing: 2) {
                    Text(Self.weekdayLetter(day))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(isToday ? Palette.textOnAccent : Palette.textQuaternary)
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? Palette.textOnAccent : Palette.textSecondary)
                    Circle()
                        .fill(count > 0 ? (isToday ? Color.white : prefs.tint) : .clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isToday ? prefs.tint : Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isToday ? .clear : Palette.border, lineWidth: 1)
                )
            }
        }
    }

    private static func weekdayLetter(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEEE"
        return f.string(from: d).uppercased()
    }

    // MARK: La grilla

    private var channelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: Space.sm)],
                  spacing: Space.sm) {
            actionChannels
            ForEach(state.visibleCourses) { course in
                courseChannel(course)
            }
        }
    }

    @ViewBuilder
    private var actionChannels: some View {
        let pendientes = upcoming.count
        let sinLeer = watcher.unseenCount

        ChannelTile(title: "Tareas",
                    subtitle: pendientes == 0 ? "nada pendiente"
                                              : "\(pendientes) por entregar",
                    eyebrow: "ENTREGAS",
                    accent: Palette.warning,
                    badge: pendientes) {
            GlyphArt(text: "", symbol: "checkmark.seal.fill")
        } action: {
            state.pendingSectionOpen = .asignaciones
        }

        ChannelTile(title: "Novedades",
                    subtitle: sinLeer == 0 ? "sin cambios" : "\(sinLeer) sin leer",
                    eyebrow: "CAMBIOS",
                    accent: Palette.danger,
                    badge: sinLeer) {
            GlyphArt(text: "", symbol: "bell.badge.fill")
        } action: {
            state.pendingSectionOpen = .novedades
        }

        ChannelTile(title: "Horario",
                    subtitle: horarioSubtitle,
                    eyebrow: "HOY",
                    accent: Palette.success) {
            GlyphArt(text: "", symbol: "calendar.badge.clock")
        } action: {
            state.pendingSectionOpen = .horario
        }

        ChannelTile(title: "Estudiar",
                    subtitle: "con el material del docente",
                    eyebrow: "REPASO",
                    accent: Palette.accentGlow) {
            GlyphArt(text: "", symbol: "brain.head.profile")
        } action: {
            state.pendingSectionOpen = .estudiar
        }

        ChannelTile(title: "Calificaciones",
                    subtitle: "sobre 300 puntos",
                    eyebrow: "NOTAS",
                    accent: Palette.bay) {
            GlyphArt(text: "", symbol: "chart.bar.fill")
        } action: {
            state.pendingSectionOpen = .notasMoodle
        }
    }

    private var horarioSubtitle: String {
        let hoy = store.slots(on: .today)
        guard let next = hoy.first else { return "sin clases hoy" }
        return "\(next.startText) · \(next.courseName)"
    }

    private func courseChannel(_ course: MoodleCourse) -> some View {
        let info = CourseInfo(course: course)
        let accent = CourseAccent.color(for: course)
        let pend = upcoming.filter { $0.courseName == info.code }.count

        return ChannelTile(title: info.name,
                           subtitle: info.group.map { "Grupo \($0)" },
                           eyebrow: info.code,
                           accent: accent,
                           badge: pend) {
            ZStack {
                GlyphArt(text: String(info.name.prefix(1)).uppercased())
                if store.isFavorite(course.id) {
                    VStack {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.25), radius: 2)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
        } action: {
            state.pendingCourseOpen = course
        }
    }

    /// La única línea que importa ya mismo: la próxima entrega.
    private var focusLine: String? {
        guard let next = upcoming.first else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .full
        return "\(next.title) · \(next.courseName) — \(f.localizedString(for: next.date, relativeTo: Date()))"
    }

    private var dateHeading: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f.string(from: Date())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12  { return "Buenos días," }
        if hour < 19  { return "Buenas tardes," }
        return "Buenas noches,"
    }

    // MARK: - Data

    struct UpcomingItem: Identifiable {
        let id: Int
        let courseName: String
        let courseAccent: Color
        let title: String
        let date: Date
    }

    private func loadUpcoming() async {
        guard !state.visibleCourses.isEmpty else { return }
        loadingUpcoming = true; defer { loadingUpcoming = false }
        do {
            let resp = try await state.moodle.assignments(courseIds: state.visibleCourses.map(\.id))
            var items: [UpcomingItem] = []
            for group in resp.courses {
                let course = state.courses.first { $0.id == group.id }
                let accent = course.map(CourseAccent.color(for:)) ?? prefs.tint
                let name = course.map { CourseInfo(course: $0).code } ?? group.shortname
                for a in group.assignments {
                    if let d = a.dueDateOrNil, d > Date() {
                        items.append(UpcomingItem(id: a.id,
                                                  courseName: name,
                                                  courseAccent: accent,
                                                  title: HTMLClean.plain(a.name),
                                                  date: d))
                    }
                }
            }
            items.sort { $0.date < $1.date }
            await MainActor.run {
                withAnimation(Motion.spring) { self.upcoming = items }
            }
        } catch {
            // silencioso; el dashboard funciona sin esto
        }
    }
}

// MARK: - Compatibilidad

/// Alias del tile de métrica; se mantiene por las vistas que ya lo usaban.
struct MiniStat: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        MetricTile(icon: icon, label: label, value: value, tint: tint)
    }
}

// MARK: - Fila de entrega

private struct UpcomingRow: View {
    let item: DashboardView.UpcomingItem
    var showTime: Bool = false
    @State private var hovered = false

    /// Rojo cuando faltan menos de 24h. El único lugar del dashboard donde
    /// se permite un color de alarma.
    private var urgent: Bool { item.date.timeIntervalSinceNow < 86_400 }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.courseAccent)
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.courseName)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(item.courseAccent)
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)

            Text(showTime ? relativeTime : relativeDate)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(urgent ? Palette.danger : Palette.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(urgent ? Palette.danger.opacity(0.12) : Color.clear)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.textPrimary.opacity(hovered ? 0.05 : 0))
        )
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .help(item.date.formatted(date: .complete, time: .shortened))
    }

    private var relativeTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: item.date)
    }

    private var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: item.date, relativeTo: Date())
    }
}

// MARK: - Course card

struct CourseCard: View {
    @EnvironmentObject private var prefs: UserPrefs
    let course: MoodleCourse
    @State private var hovered = false
    @ObservedObject private var store = LocalStore.shared

    var body: some View {
        let info = CourseInfo(course: course)
        let accent = CourseAccent.color(for: course)
        let isFav = store.isFavorite(course.id)
        let radius = Radius.lg

        VStack(alignment: .leading, spacing: 0) {
            cover(info: info, accent: accent, isFav: isFav, radius: radius)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(info.code)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(accent)
                    if let g = info.group {
                        Text("Grupo \(g)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if store.rating(for: course.id) > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7.5))
                            Text("\(store.rating(for: course.id))")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Palette.gold)
                    }
                }

                Text(info.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: Space.xs)

                HStack(spacing: 6) {
                    if let period = info.period, let year = info.year {
                        Text("\(period)C · \(year)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hovered ? accent : Palette.textQuaternary)
                        .offset(x: hovered ? 3 : 0)
                }
            }
            .padding(prefs.padLarge)
        }
        .frame(minHeight: prefs.density == .compact ? 196 : 224, alignment: .topLeading)
        .adaptiveSurface(prefs, cornerRadius: radius, elevation: hovered ? .high : .low)
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(accent.opacity(hovered ? 0.45 : 0), lineWidth: 1)
        }
        .shadow(color: accent.opacity(hovered ? 0.22 : 0), radius: hovered ? 20 : 0, x: 0, y: 9)
        .scaleEffect(hovered ? 1.008 : 1)
        .offset(y: hovered ? -2 : 0)
        .contentShape(Rectangle())
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .contextMenu { contextMenu }
    }

    // MARK: Cover

    private func cover(info: CourseInfo, accent: Color,
                       isFav: Bool, radius: CGFloat) -> some View {
        // La "lámina" del capítulo: recortada en arco ojival, como el ventanal
        // de un claustro. Si Moodle no trae imagen, se llena con la inicial del
        // código en capitular sobre la aguada de grafito.
        ZStack(alignment: .topTrailing) {
            RemoteImage(url: course.imageURL, contentMode: .fill) {
                ZStack {
                    CourseAccent.gradient(for: course)
                    Text(String(info.code.prefix(1)))
                        .font(.system(size: 78, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.16))
                }
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.4),
                        .init(color: .black.opacity(0.30), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipShape(GothicArch(shoulder: 0.5))
            .overlay {
                GothicArch(shoulder: 0.5)
                    .stroke(Palette.textOnAccent.opacity(0.28), lineWidth: 1)
            }
            .overlay {
                CornerFrame(color: .white.opacity(0.5), length: 12)
                    .padding(6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .scaleEffect(hovered ? 1.015 : 1, anchor: .center)
            .animation(Motion.spring, value: hovered)

            Button {
                withAnimation(Motion.pop) { store.toggleFavorite(course.id) }
            } label: {
                Image(systemName: isFav ? "seal.fill" : "seal")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isFav ? Palette.textOnAccent : .white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.black.opacity(isFav ? 0.4 : 0.25)))
                    .symbolEffect(.bounce, value: isFav)
            }
            .buttonStyle(.plain)
            .padding(20)
            .help(isFav ? "Quitar del cofre" : "Guardar en el cofre")
        }
    }

    // MARK: Context menu

    @ViewBuilder private var contextMenu: some View {
        Button {
            store.toggleFavorite(course.id)
        } label: {
            Label(store.isFavorite(course.id) ? "Quitar de favoritos" : "Marcar como favorito",
                  systemImage: store.isFavorite(course.id) ? "star.slash" : "star")
        }
        Divider()
        Menu("Dificultad") {
            ForEach(1...5, id: \.self) { r in
                Button {
                    store.setRating(r, for: course.id)
                } label: {
                    Label(String(repeating: "★", count: r) + String(repeating: "☆", count: 5 - r),
                          systemImage: store.rating(for: course.id) == r ? "checkmark" : "")
                }
            }
            Divider()
            Button("Sin calificación") { store.setRating(0, for: course.id) }
        }
        Divider()
        Button {
            if let url = URL(string: "uamclass://course/\(course.id)") {
                PlatformBridge.copyToClipboard(url.absoluteString)
                ToastCenter.shared.show("Link copiado", symbol: "link", tint: prefs.tint)
            }
        } label: {
            Label("Copiar enlace", systemImage: "link")
        }
    }
}

struct MetaPill: View {
    let label: String
    var body: some View {
        Pill(text: label, tone: .neutral, compact: true)
    }
}
