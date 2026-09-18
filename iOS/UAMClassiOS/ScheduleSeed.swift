import Foundation

/// Trae el horario que ya tenías cargado en la Mac (leído directo de su
/// `UserDefaults` al portar la app) para que no lo tengas que escribir de
/// nuevo a mano en el teléfono. Se aplica UNA sola vez: si ya cargaste o
/// editaste algo en el horario del teléfono, no lo toca ni lo pisa.
enum ScheduleSeed {
    @MainActor
    static func applyIfNeeded() {
        let flagKey = "UAMClass.scheduleSeeded.v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        UserDefaults.standard.set(true, forKey: flagKey)

        guard LocalStore.shared.schedule.isEmpty else { return }

        let slots: [ClassSlot] = [
            ClassSlot(courseName: "Ingeniería de Software II", section: "SIS0404 · Grupo 1",
                      weekday: .lunes, room: "C-108", startMinutes: 960, endMinutes: 1070),
            ClassSlot(courseName: "B2 Communicative English", section: "CEP0006 · Grupo 6",
                      weekday: .martes, room: "B-202", startMinutes: 780, endMinutes: 950),
            ClassSlot(courseName: "Arquitectura de Computadoras", section: "SIS0308 · Grupo 1",
                      weekday: .miercoles, room: "B-101", startMinutes: 960, endMinutes: 1120),
            ClassSlot(courseName: "Servicios Web", section: "SIS0421 · Grupo 2",
                      weekday: .miercoles, room: "C-205", startMinutes: 1125, endMinutes: 1280),
            ClassSlot(courseName: "B2 Communicative English", section: "CEP0006 · Grupo 6",
                      weekday: .jueves, room: "B-202", startMinutes: 780, endMinutes: 950),
            ClassSlot(courseName: "Ingeniería de Software II", section: "SIS0404 · Grupo 1",
                      weekday: .jueves, room: "C-108", startMinutes: 960, endMinutes: 1070),
            ClassSlot(courseName: "Inteligencia de Negocios", section: "SIS0408 · Grupo 2",
                      weekday: .viernes, room: "C-205", startMinutes: 1070, endMinutes: 1230),
        ]
        for slot in slots {
            LocalStore.shared.upsertSlot(slot)
        }
    }
}
