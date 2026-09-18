import SwiftUI
import AppKit

struct ArchiverSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service: ArchiveService

    @State private var selected: Set<Int> = []
    @State private var started = false

    init(moodle: MoodleClient) {
        _service = StateObject(wrappedValue: ArchiveService(moodle: moodle))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            if service.progress.isRunning || service.progress.finishedFolder != nil {
                progressPane
            } else {
                selectionPane
            }
        }
        .frame(width: 640, height: 580)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.55))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "archivebox.fill", tint: prefs.tint, size: 32, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Archivar semestre")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(periodLabel)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            GlassIconButton(symbol: "xmark", help: "Cerrar", size: 24) {
                if service.progress.isRunning { service.cancel() }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(Space.md)
    }

    // MARK: Selection

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Elegí qué cursos archivar")
                    .font(Type.subtitle).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    if selected.count == state.visibleCourses.count {
                        selected.removeAll()
                    } else {
                        selected = Set(state.visibleCourses.map(\.id))
                    }
                } label: {
                    Text(selected.count == state.visibleCourses.count ? "Ninguno" : "Todos")
                        .font(Type.caption).foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.visibleCourses) { c in
                        courseRow(c)
                    }
                }
                .adaptiveSurface(prefs, cornerRadius: Radius.md)
            }
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 6) {
                Label("Destino", systemImage: "folder")
                    .font(Type.caption).foregroundStyle(Palette.textSecondary)
                Text(destinationPreview)
                    .font(Type.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adaptiveSurface(prefs, cornerRadius: Radius.sm, elevation: .flat)
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(selected.count) de \(state.visibleCourses.count) seleccionados")
                    .font(Type.caption).foregroundStyle(Palette.textTertiary)
                Spacer()
                PrimaryButton(
                    title: "Empezar",
                    loading: false,
                    disabled: selected.isEmpty
                ) {
                    started = true
                    let courses = state.visibleCourses.filter { selected.contains($0.id) }
                    let uid = state.moodleSiteInfo?.userid ?? 0
                    Task { await service.archive(courses: courses, userId: uid, periodLabel: periodLabel) }
                }
                .frame(width: 160)
            }
        }
        .padding(Space.md)
        .onAppear {
            if selected.isEmpty { selected = Set(state.visibleCourses.map(\.id)) }
        }
    }

    private func courseRow(_ c: MoodleCourse) -> some View {
        let info = CourseInfo(course: c)
        let picked = selected.contains(c.id)
        let accent = CourseAccent.color(for: c)
        return HStack(spacing: 10) {
            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(picked ? prefs.tint : Palette.textQuaternary)
                .symbolEffect(.bounce, value: picked)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(info.code)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Text(info.name)
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            Text(info.meta)
                .font(Type.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.quick) {
                if picked { selected.remove(c.id) } else { selected.insert(c.id) }
            }
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(Palette.divider).padding(.leading, 40)
        }
    }

    // MARK: Progress

    private var progressPane: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                if service.progress.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Descargando…").font(Type.bodyBold).foregroundStyle(Palette.textPrimary)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                    Text("Terminado").font(Type.bodyBold).foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(service.progress.doneCourses)/\(service.progress.totalCourses) cursos")
                    .font(Type.caption).foregroundStyle(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                AccentBar(value: overallFraction, tint: prefs.tint, height: 7)
                HStack {
                    Text("\(service.progress.doneFiles) / \(max(service.progress.totalFiles, 1)) archivos")
                        .font(Type.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Text("\(Int(overallFraction * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(prefs.tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Actual").labelCaps()
                Text(service.progress.currentCourse.isEmpty ? "—" : service.progress.currentCourse)
                    .font(Type.bodyBold).foregroundStyle(Palette.textPrimary)
                Text(service.progress.currentStep)
                    .font(Type.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveSurface(prefs, cornerRadius: Radius.md)

            if !service.progress.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avisos (\(service.progress.errors.count))").labelCaps()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(service.progress.errors.indices, id: \.self) { i in
                                Text(service.progress.errors[i])
                                    .font(Type.caption).foregroundStyle(Palette.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 90)
                    .scrollContentBackground(.hidden)
                    .adaptiveSurface(prefs, cornerRadius: Radius.sm, elevation: .flat)
                }
            }

            Spacer(minLength: 0)

            HStack {
                if service.progress.isRunning {
                    SecondaryButton(title: "Cancelar") {
                        service.cancel()
                    }
                }
                Spacer()
                if let folder = service.progress.finishedFolder {
                    PrimaryButton(title: "Mostrar en Finder", icon: "folder", fullWidth: false) {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    .frame(width: 210)
                }
            }
        }
        .padding(Space.md)
    }

    private var overallFraction: Double {
        let total = max(service.progress.totalFiles, 1)
        return min(1.0, Double(service.progress.doneFiles) / Double(total))
    }

    // MARK: - Utils

    private var periodLabel: String {
        // Toma el año y periodo más frecuente entre los cursos.
        let periods = state.visibleCourses.map { CourseInfo(course: $0) }
            .compactMap { info -> String? in
                guard let y = info.year, let p = info.period else { return nil }
                return "\(y)-\(p)"
            }
        return periods.first ?? "Semestre"
    }

    private var destinationPreview: String {
        let home = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
        return "\(home)/UAM Class/\(periodLabel)/"
    }
}
