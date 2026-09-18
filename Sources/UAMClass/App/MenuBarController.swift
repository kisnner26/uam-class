import AppKit
import SwiftUI

/// Widget en la barra de menú con popover rico (mini dashboard).
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var upcoming: [MoodleAssignment] = []
    private var courseByAssignId: [Int: MoodleCourse] = [:]

    override init() {
        super.init()
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "graduationcap.fill",
                                   accessibilityDescription: "UAM Class")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 390)
        popover.contentViewController = hostingController(upcoming: [], coursesById: [:])
    }

    /// El popover vive fuera del `WindowGroup`, así que hay que inyectarle a
    /// mano el entorno que las vistas compartidas esperan (tint, densidad).
    private func hostingController(upcoming: [MoodleAssignment],
                                   coursesById: [Int: MoodleCourse]) -> NSHostingController<some View> {
        let root = MenuBarPopoverContent(
            upcoming: upcoming,
            coursesById: coursesById,
            onOpenApp: { [weak self] in self?.openMainWindow() },
            onOpenPalette: { [weak self] in self?.openPalette() }
        )
        .environmentObject(UserPrefs.shared)
        return NSHostingController(rootView: root)
    }

    func update(upcoming: [MoodleAssignment], coursesById: [Int: MoodleCourse]) {
        self.upcoming = upcoming
        self.courseByAssignId = coursesById
        popover.contentViewController = hostingController(upcoming: upcoming,
                                                          coursesById: coursesById)

        // Badge con contador si hay entregas próximas (24h)
        if let button = statusItem.button {
            let soon = upcoming.filter {
                guard let d = $0.dueDateOrNil else { return false }
                return d.timeIntervalSince(Date()) < 24 * 3600
            }.count
            if soon > 0 {
                button.title = " \(soon)"
            } else {
                button.title = ""
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func openMainWindow() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows { window.makeKeyAndOrderFront(nil) }
    }

    @objc private func openPalette() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows { window.makeKeyAndOrderFront(nil) }
        NotificationCenter.default.post(name: .init("UAMClass.OpenPalette"), object: nil)
    }
}

// MARK: - Popover content

struct MenuBarPopoverContent: View {
    let upcoming: [MoodleAssignment]
    let coursesById: [Int: MoodleCourse]
    let onOpenApp: () -> Void
    let onOpenPalette: () -> Void

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.divider)
            content
            Divider().overlay(Palette.divider)
            footer
        }
        .frame(width: 330, height: 390)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.7))
        .tint(prefs.tint)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("UAM Class")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(upcoming.isEmpty
                     ? "Sin entregas próximas"
                     : "\(upcoming.count) entrega\(upcoming.count == 1 ? "" : "s") pendiente\(upcoming.count == 1 ? "" : "s")")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        if upcoming.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                ZStack {
                    Circle().fill(Palette.success.opacity(0.12))
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.success)
                }
                .frame(width: 48, height: 48)
                Text("Todo bajo control")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Ninguna entrega pendiente por ahora.")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(upcoming.prefix(10).enumerated()), id: \.element.id) { i, a in
                        popoverRow(a: a, isLast: i == min(upcoming.count, 10) - 1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func popoverRow(a: MoodleAssignment, isLast: Bool) -> some View {
        let course = coursesById[a.id]
        let accent: Color = course.map(CourseAccent.color(for:)) ?? Palette.accent
        let code = course.map { CourseInfo(course: $0).code } ?? ""

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(accent).frame(width: 3, height: 26).cornerRadius(2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(code)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                    Text(HTMLClean.plain(a.name))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                if let d = a.dueDateOrNil {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(d, style: .relative)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(d.timeIntervalSince(Date()) < 3600 ? Palette.danger : Palette.textSecondary)
                        Text(d.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if !isLast {
                Divider().background(Palette.divider).padding(.leading, 24)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            GhostButton(title: "Buscar", icon: "magnifyingglass", action: onOpenPalette)
            Spacer()
            Button(action: onOpenApp) {
                HStack(spacing: 4) {
                    Text("Abrir UAM Class")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(prefs.tint.brandGradient))
                .overlay(Capsule().strokeBorder(Palette.rimOnDark, lineWidth: 0.6))
                .shadow(color: prefs.tint.opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }
}
