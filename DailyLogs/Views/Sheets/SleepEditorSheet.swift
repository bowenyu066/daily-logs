import SwiftUI

enum SleepEditorTarget: String, Identifiable {
    case bedtime
    case wakeTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bedtime: NSLocalizedString("前一晚入睡", comment: "")
        case .wakeTime: NSLocalizedString("当天起床", comment: "")
        }
    }

    var accent: Color {
        switch self {
        case .bedtime: AppTheme.sleepAccent
        case .wakeTime: AppTheme.wakeAccent
        }
    }
}

struct SleepEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var selectedTime: Date

    let target: SleepEditorTarget
    let hasExistingValue: Bool
    let baseDate: Date
    let onSave: (Date?) -> Void

    init(
        target: SleepEditorTarget,
        currentValue: Date?,
        baseDate: Date,
        onSave: @escaping (Date?) -> Void
    ) {
        self.target = target
        self.hasExistingValue = currentValue != nil
        self.baseDate = baseDate.startOfDay
        self.onSave = onSave

        let defaultValue: Date
        switch target {
        case .bedtime:
            defaultValue = currentValue ?? baseDate.adding(days: -1).settingTime(hour: 23, minute: 30)
        case .wakeTime:
            defaultValue = currentValue ?? baseDate.settingTime(hour: 7, minute: 30)
        }
        _selectedTime = State(initialValue: defaultValue)
    }

    var body: some View {
        VStack(spacing: 24) {
            headerBar

            VStack(spacing: 10) {
                Text(target.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)

                Text(appViewModel.displayedClockTime(
                    for: selectedTime,
                    recordedTimeZoneIdentifier: appViewModel.dailyRecord.sleepRecord.timeZoneIdentifier
                ))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(target.accent)
                    .monospacedDigit()
            }

            DatePicker(
                "",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.timeZone, appViewModel.displayedTimeZone(for: appViewModel.dailyRecord.sleepRecord.timeZoneIdentifier))

            if hasExistingValue {
                Button(NSLocalizedString("清除记录", comment: ""), role: .destructive) {
                    onSave(nil)
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        ZStack {
            Text(target == .bedtime ? NSLocalizedString("入睡时间", comment: "") : NSLocalizedString("起床时间", comment: ""))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)

                Spacer()

                Button(NSLocalizedString("保存", comment: "")) {
                    onSave(normalizedTime)
                    dismiss()
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private var normalizedTime: Date {
        let timeZone = appViewModel.displayedTimeZone(for: appViewModel.dailyRecord.sleepRecord.timeZoneIdentifier)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? 23
        let minute = components.minute ?? 30

        switch target {
        case .bedtime:
            if hour >= 12 {
                return baseDate.adding(days: -1).settingTime(hour: hour, minute: minute, in: timeZone)
            } else {
                return baseDate.settingTime(hour: hour, minute: minute, in: timeZone)
            }
        case .wakeTime:
            return baseDate.settingTime(hour: hour, minute: minute, in: timeZone)
        }
    }
}

struct SleepNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftNote: String

    let onSave: (String?) -> Void

    init(note: String?, onSave: @escaping (String?) -> Void) {
        _draftNote = State(initialValue: note ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    RecordNoteSection(note: $draftNote)
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("睡眠备注", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        onSave(draftNote)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RecordNoteSection: View {
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("备注", comment: ""))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            TextField(NSLocalizedString("备注", comment: ""), text: $note, axis: .vertical)
                .font(.system(size: 16, design: .rounded))
                .lineLimit(3, reservesSpace: false)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
