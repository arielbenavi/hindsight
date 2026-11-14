import SwiftUI

/// F5: make a routine a Regular. Weekday chips (M T W T F S S) + a time, with presets.
/// Saving pins it to Regulars and schedules repeating notifications.
struct RegularScheduleSheet: View {
    let app: AppModel
    let routine: Routine

    @State private var weekdays: Set<Int>
    @State private var time: Date
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    /// Monday first. Values are `Calendar` weekdays (1 = Sunday … 7 = Saturday).
    private static let order = [2, 3, 4, 5, 6, 7, 1]
    private static let everyDay = Set(1...7)
    private static let weekdaysOnly = Set(2...6)
    private static let monWedFri: Set<Int> = [2, 4, 6]

    init(app: AppModel, routine: Routine) {
        self.app = app
        self.routine = routine
        let existing = app.practice.screen(.fitness).regulars[routine.id]
        _weekdays = State(initialValue: existing?.weekdays ?? Self.monWedFri)
        let hour = existing?.hour ?? 8
        let minute = existing?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now)
    }

    private var existing: RegularSchedule? { app.practice.screen(.fitness).regulars[routine.id] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Do \(Text(routine.title).italic().foregroundStyle(Theme.lime)) on")
                        .font(Theme.title(28))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        ForEach(Self.order, id: \.self) { day in
                            dayChip(day)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick picks").font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.secondary)
                        WrapLayout(spacing: 8) {
                            Chip(label: "Every morning", isSelected: weekdays == Self.everyDay && isMorning) {
                                weekdays = Self.everyDay
                                time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? time
                            }
                            Chip(label: "Weekdays", isSelected: weekdays == Self.weekdaysOnly) { weekdays = Self.weekdaysOnly }
                            Chip(label: "3× a week", isSelected: weekdays == Self.monWedFri) { weekdays = Self.monWedFri }
                        }
                    }

                    HStack {
                        Text("At").font(Theme.body(17, weight: .bold))
                        Spacer()
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .card(padding: 16)

                    Text(preview).font(Theme.body(15)).foregroundStyle(Theme.secondary)

                    VStack(spacing: 12) {
                        Button(existing == nil ? "Make it a regular" : "Save", action: save)
                            .buttonStyle(.pill)
                            .disabled(weekdays.isEmpty || saving)
                        if existing != nil {
                            Button("Remove from regulars", role: .destructive) {
                                app.practice.removeRegular(routine.id)
                                app.rescheduleReminders()
                                dismiss()
                            }
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(Theme.padding)
                .animation(.snappy, value: weekdays)
            }
            .themedScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func dayChip(_ day: Int) -> some View {
        let on = weekdays.contains(day)
        let symbol = Calendar.current.veryShortWeekdaySymbols[day - 1]
        return Button {
            if on { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(symbol)
                .font(Theme.body(16, weight: .heavy))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(on ? Theme.onLime : Theme.text)
                .background(on ? Theme.lime : Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(on ? .clear : Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: on)
    }

    private var components: (hour: Int, minute: Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 8, c.minute ?? 0)
    }

    private var isMorning: Bool { components.hour == 8 && components.minute == 0 }

    private var schedule: RegularSchedule {
        RegularSchedule(routineID: routine.id, weekdays: weekdays, hour: components.hour, minute: components.minute)
    }

    private var preview: String {
        weekdays.isEmpty ? "Pick at least one day." : "\(schedule.summary). We'll send a gentle reminder."
    }

    private func save() {
        saving = true
        app.practice.setRegular(schedule)
        Task {
            _ = await ReminderScheduler.shared.requestAuthorization()
            app.rescheduleReminders()
            dismiss()
        }
    }
}

#Preview {
    let app = FitnessPreview.app()
    Color.clear.sheet(isPresented: .constant(true)) {
        RegularScheduleSheet(app: app, routine: app.fitness!.routines[0])
    }
}
