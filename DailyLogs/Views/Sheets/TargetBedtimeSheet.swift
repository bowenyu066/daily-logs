import SwiftUI

struct TargetBedtimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: BedtimeSchedule
    @State private var selectedWeekdays: Set<Weekday>
    let onSave: (BedtimeSchedule) -> Void

    init(initialValue: BedtimeSchedule, onSave: @escaping (BedtimeSchedule) -> Void) {
        _schedule = State(initialValue: initialValue)
        let today = Weekday(rawValue: Date.now.isoWeekday) ?? .monday
        _selectedWeekdays = State(initialValue: [today])
        self.onSave = onSave
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    headerBar
                        .padding(.top, topInset(for: proxy))

                    HStack(spacing: 10) {
                        ForEach(Weekday.allCases) { weekday in
                            Button {
                                toggleWeekday(weekday)
                            } label: {
                                Text(weekday.shortLabel)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(selectedWeekdays.contains(weekday) ? Color.white : AppTheme.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(selectedWeekdays.contains(weekday) ? AppTheme.accent : AppTheme.surface)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(displayTimeForSelection)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: { updateSelectedWeekdays(with: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxHeight: 170)
                    .clipped()
                }
                .padding(.horizontal, 24)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Weekday.allCases) { weekday in
                            Button {
                                toggleWeekday(weekday)
                            } label: {
                                HStack {
                                    Text(weekday.title)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.primaryText)
                                    Spacer()
                                    Text(time(for: weekday).displayTime)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(selectedWeekdays.contains(weekday) ? AppTheme.accent : AppTheme.secondaryText)
                                    if selectedWeekdays.contains(weekday) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(selectedWeekdays.contains(weekday) ? AppTheme.accentSoft : AppTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 24, 36))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(AppTheme.background.ignoresSafeArea())
        }
    }

    private var headerBar: some View {
        ZStack {
            Text(String(localized: "目标入睡"))
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

    private var displayTimeForSelection: String {
        guard let first = selectedWeekdays.sorted(by: { $0.rawValue < $1.rawValue }).first else {
            return "--:--"
        }
        return time(for: first).displayTime
    }

    private var selectedDate: Date {
        let first = selectedWeekdays.sorted(by: { $0.rawValue < $1.rawValue }).first
        let t = first.map { time(for: $0) } ?? DateComponents(hour: 23, minute: 30)
        return Calendar.current.date(from: DateComponents(
            year: 2001,
            month: 1,
            day: 1,
            hour: t.hour ?? 23,
            minute: t.minute ?? 30
        )) ?? .now
    }

    private func time(for weekday: Weekday) -> DateComponents {
        schedule.entries.first(where: { $0.weekday == weekday })?.time ?? DateComponents(hour: 23, minute: 30)
    }

    private func toggleWeekday(_ weekday: Weekday) {
        if selectedWeekdays.contains(weekday) {
            if selectedWeekdays.count > 1 {
                selectedWeekdays.remove(weekday)
            }
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func updateSelectedWeekdays(with date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        for weekday in selectedWeekdays {
            if let index = schedule.entries.firstIndex(where: { $0.weekday == weekday }) {
                schedule.entries[index].time = components
            }
        }
    }

    private func topInset(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.top + 12, 52)
    }
}
