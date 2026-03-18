import SwiftUI

struct SexualActivityEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var dateOnly: Bool
    @State private var draftTime: Date
    @State private var isMasturbation: Bool
    @State private var draftNote: String

    let baseDate: Date
    let isEditable: Bool
    let onSave: (SexualActivityEntry) -> Void
    let onDelete: (() -> Void)?

    private let entryID: UUID
    private let recordedTimeZoneIdentifier: String?

    init(
        initialValue: SexualActivityEntry,
        baseDate: Date,
        isEditable: Bool,
        onSave: @escaping (SexualActivityEntry) -> Void,
        onDelete: (() -> Void)?
    ) {
        _dateOnly = State(initialValue: initialValue.time == nil)
        _draftTime = State(initialValue: initialValue.time ?? baseDate.settingTime(hour: 22, minute: 0, in: .autoupdatingCurrent))
        _isMasturbation = State(initialValue: initialValue.isMasturbation)
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
                    .padding(.top, 8)

                Toggle(NSLocalizedString("仅记录有/无", comment: ""), isOn: $dateOnly)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(.pink)
                    .disabled(!isEditable)
                    .padding(.horizontal, 4)

                if !dateOnly {
                    Text(appViewModel.displayedClockTime(
                        for: draftTime,
                        recordedTimeZoneIdentifier: recordedTimeZoneIdentifier
                    ))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.pink)
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

                if appViewModel.preferences.showMasturbationOption {
                    Toggle(NSLocalizedString("自慰", comment: ""), isOn: $isMasturbation)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .tint(.pink)
                        .disabled(!isEditable)
                        .padding(.horizontal, 4)
                }

                RecordNoteSection(note: $draftNote)
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
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        ZStack {
            Text(NSLocalizedString("性生活", comment: ""))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)

                Spacer()

                Button(NSLocalizedString("保存", comment: "")) {
                    let timeZone = appViewModel.displayedTimeZone(for: recordedTimeZoneIdentifier)
                    let resolvedTime: Date? = dateOnly ? nil : normalizedTime(in: timeZone)
                    onSave(
                        SexualActivityEntry(
                            id: entryID,
                            date: baseDate,
                            time: resolvedTime,
                            isMasturbation: appViewModel.preferences.showMasturbationOption ? isMasturbation : false,
                            timeZoneIdentifier: resolvedTime != nil ? timeZone.identifier : nil,
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

    private func normalizedTime(in timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: draftTime)
        return baseDate.settingTime(hour: components.hour ?? 22, minute: components.minute ?? 0, in: timeZone)
    }
}
