import SwiftUI

struct TargetBedtimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: BedtimeSchedule
    @State private var selectedWeekday: Weekday
    let onSave: (BedtimeSchedule) -> Void

    init(initialValue: BedtimeSchedule, onSave: @escaping (BedtimeSchedule) -> Void) {
        _schedule = State(initialValue: initialValue)
        _selectedWeekday = State(initialValue: Weekday(rawValue: Date.now.isoWeekday) ?? .monday)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 20) {
            headerBar
                .padding(.top, 30)

            HStack(spacing: 10) {
                ForEach(Weekday.allCases) { weekday in
                    Button {
                        selectedWeekday = weekday
                    } label: {
                        Text(weekday.shortLabel)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedWeekday == weekday ? Color.white : AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(selectedWeekday == weekday ? AppTheme.accent : AppTheme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(selectedTime.displayTime)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            DatePicker(
                "",
                selection: Binding(
                    get: { selectedDate },
                    set: { updateSelectedWeekday(with: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxHeight: 170)
            .clipped()

            VStack(spacing: 10) {
                ForEach(Weekday.allCases) { weekday in
                    Button {
                        selectedWeekday = weekday
                    } label: {
                        HStack {
                            Text(weekday.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            Text(time(for: weekday).displayTime)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(selectedWeekday == weekday ? AppTheme.accent : AppTheme.secondaryText)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(AppTheme.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        ZStack {
            Text("目标入睡")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            HStack {
                headerIconButton(systemImage: "xmark") {
                    dismiss()
                }

                Spacer()

                headerIconButton(systemImage: "checkmark") {
                    onSave(schedule)
                    dismiss()
                }
            }
        }
    }

    private func headerIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 48, height: 48)
                .background(AppTheme.surface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var selectedTime: DateComponents {
        time(for: selectedWeekday)
    }

    private var selectedDate: Date {
        Calendar.current.date(from: DateComponents(
            year: 2001,
            month: 1,
            day: 1,
            hour: selectedTime.hour ?? 23,
            minute: selectedTime.minute ?? 30
        )) ?? .now
    }

    private func time(for weekday: Weekday) -> DateComponents {
        schedule.entries.first(where: { $0.weekday == weekday })?.time ?? DateComponents(hour: 23, minute: 30)
    }

    private func updateSelectedWeekday(with date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        if let index = schedule.entries.firstIndex(where: { $0.weekday == selectedWeekday }) {
            schedule.entries[index].time = components
        }
    }
}
