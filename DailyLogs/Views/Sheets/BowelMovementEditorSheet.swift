import SwiftUI

struct BowelMovementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var draftTime: Date

    let baseDate: Date
    let isEditable: Bool
    let onSave: (BowelMovementEntry) -> Void
    let onDelete: (() -> Void)?

    private let entryID: UUID
    private let recordedTimeZoneIdentifier: String?

    init(
        initialValue: BowelMovementEntry,
        baseDate: Date,
        isEditable: Bool,
        onSave: @escaping (BowelMovementEntry) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draftTime = State(initialValue: initialValue.time)
        self.entryID = initialValue.id
        self.recordedTimeZoneIdentifier = initialValue.timeZoneIdentifier
        self.baseDate = baseDate
        self.isEditable = isEditable
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 16) {
            headerBar
                .padding(.top, 8)

            Text(appViewModel.displayedClockTime(
                for: draftTime,
                recordedTimeZoneIdentifier: recordedTimeZoneIdentifier
            ))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.brown)
                .monospacedDigit()

            DatePicker(
                "",
                selection: $draftTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxHeight: 150)
            .clipped()
            .disabled(!isEditable)
            .environment(\.timeZone, appViewModel.displayedTimeZone(for: recordedTimeZoneIdentifier))

            if let onDelete {
                Button(NSLocalizedString("删除记录", comment: ""), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        ZStack {
            Text(NSLocalizedString("排便时间", comment: ""))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)

                Spacer()

                Button(NSLocalizedString("保存", comment: "")) {
                    onSave(
                        BowelMovementEntry(
                            id: entryID,
                            time: normalizedTime
                        )
                    )
                    dismiss()
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .disabled(!isEditable)
            }
        }
    }

    private var normalizedTime: Date {
        let timeZone = appViewModel.displayedTimeZone(for: recordedTimeZoneIdentifier)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: draftTime)
        return baseDate.settingTime(hour: components.hour ?? 8, minute: components.minute ?? 0, in: timeZone)
    }
}
