import SwiftUI

struct ShowerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftTime: Date

    let baseDate: Date
    let isEditable: Bool
    let onSave: (ShowerEntry) -> Void
    let onDelete: (() -> Void)?

    private let entryID: UUID

    init(
        initialValue: ShowerEntry,
        baseDate: Date,
        isEditable: Bool,
        onSave: @escaping (ShowerEntry) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draftTime = State(initialValue: initialValue.time)
        self.entryID = initialValue.id
        self.baseDate = baseDate
        self.isEditable = isEditable
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 16) {
            headerBar
                .padding(.top, 8)

            Text(draftTime.displayClockTime)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.showerAccent)
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
            Text(NSLocalizedString("洗澡时间", comment: ""))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)

                Spacer()

                Button(NSLocalizedString("保存", comment: "")) {
                    onSave(
                        ShowerEntry(
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
        let components = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
        return baseDate.settingTime(hour: components.hour ?? 21, minute: components.minute ?? 30)
    }
}
