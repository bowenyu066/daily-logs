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

                Text(selectedTime.displayClockTime)
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
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? 23
        let minute = components.minute ?? 30

        switch target {
        case .bedtime:
            if hour >= 12 {
                return baseDate.adding(days: -1).settingTime(hour: hour, minute: minute)
            } else {
                return baseDate.settingTime(hour: hour, minute: minute)
            }
        case .wakeTime:
            return baseDate.settingTime(hour: hour, minute: minute)
        }
    }
}
