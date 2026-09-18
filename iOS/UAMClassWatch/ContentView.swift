import SwiftUI

struct ContentView: View {
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let next = nextSlot {
                    nextCard(next)

                    let rest = todayRemaining.dropFirst()
                    if !rest.isEmpty {
                        Text("MÁS HOY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(Array(rest)) { slot in
                            slotRow(slot)
                        }
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle("UAM Class")
    }

    // MARK: - Datos

    private var nowMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Lo que queda de hoy, ordenado, incluyendo una clase en curso.
    private var todayRemaining: [ClassSlot] {
        connectivity.schedule
            .filter { $0.weekday == .today && $0.endMinutes >= nowMinutes }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// La próxima clase: si hoy no queda ninguna, la primera de los próximos días.
    private var nextSlot: ClassSlot? {
        if let today = todayRemaining.first { return today }
        let order = Weekday.week
        guard let todayIdx = order.firstIndex(of: .today) else {
            return connectivity.schedule.min { $0.startMinutes < $1.startMinutes }
        }
        for offset in 1...7 {
            let day = order[(todayIdx + offset) % order.count]
            let candidates = connectivity.schedule.filter { $0.weekday == day }
            if let first = candidates.min(by: { $0.startMinutes < $1.startMinutes }) {
                return first
            }
        }
        return nil
    }

    private var isNextInProgress: Bool {
        guard let n = nextSlot, n.weekday == .today else { return false }
        return n.startMinutes <= nowMinutes && nowMinutes < n.endMinutes
    }

    // MARK: - UI

    private func nextCard(_ slot: ClassSlot) -> some View {
        let today = slot.weekday == .today
        return VStack(alignment: .leading, spacing: 5) {
            Text(isNextInProgress ? "EN CURSO"
                 : today ? "PRÓXIMA CLASE"
                 : "PRÓXIMA · \(slot.weekday.label.uppercased())")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.teal)

            Text(slot.courseName)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Label(slot.rangeText, systemImage: "clock")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if !slot.section.isEmpty || slot.roomText != nil {
                Label(locationLine(slot), systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.teal.opacity(0.18)))
    }

    private func slotRow(_ slot: ClassSlot) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(slot.startText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.courseName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !slot.section.isEmpty || slot.roomText != nil {
                    Text(locationLine(slot))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func locationLine(_ slot: ClassSlot) -> String {
        [slot.section, slot.roomText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Sin horario todavía")
                .font(.system(size: 12, weight: .semibold))
            Text("Abrí UAM Class en tu iPhone para sincronizarlo")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }
}
