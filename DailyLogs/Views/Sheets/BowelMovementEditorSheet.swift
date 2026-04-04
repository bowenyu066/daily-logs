import SwiftUI

struct BowelMovementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var draftTime: Date
    @State private var logsExistenceOnly: Bool
    @State private var draftNote: String
    @State private var showingDeleteConfirmation = false

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
        let fallbackTime = initialValue.time ?? baseDate.anchoringCurrentClockTime()
        _draftTime = State(initialValue: fallbackTime)
        _logsExistenceOnly = State(initialValue: initialValue.time == nil)
        _draftNote = State(initialValue: initialValue.note ?? "")
        self.entryID = initialValue.id
        self.recordedTimeZoneIdentifier = initialValue.timeZoneIdentifier
        self.baseDate = baseDate
        self.isEditable = isEditable
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerBar
                    .padding(.top, 24)

                Toggle(NSLocalizedString("仅记录有/无", comment: ""), isOn: $logsExistenceOnly)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(.brown)
                    .disabled(!isEditable)
                    .padding(.horizontal, 4)

                if !logsExistenceOnly {
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
                }

                RecordNoteSection(note: $draftNote)
                    .disabled(!isEditable)

                if onDelete != nil {
                    Button(NSLocalizedString("删除记录", comment: ""), role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .alert(NSLocalizedString("删除记录？", comment: ""), isPresented: $showingDeleteConfirmation) {
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("删除记录", comment: ""), role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text(NSLocalizedString("此操作无法撤销。", comment: ""))
        }
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
                            time: logsExistenceOnly ? nil : normalizedTime,
                            timeZoneIdentifier: logsExistenceOnly ? nil : appViewModel.displayedTimeZone(for: recordedTimeZoneIdentifier).identifier,
                            note: draftNote
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
        return baseDate.settingTime(hour: components.hour ?? 12, minute: components.minute ?? 0, in: timeZone)
    }
}
