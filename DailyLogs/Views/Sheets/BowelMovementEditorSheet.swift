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
    private let travelContext: TravelRecordContext?

    init(
        initialValue: BowelMovementEntry,
        baseDate: Date,
        fallbackTime: Date,
        isEditable: Bool,
        onSave: @escaping (BowelMovementEntry) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draftTime = State(initialValue: initialValue.time ?? fallbackTime)
        _logsExistenceOnly = State(initialValue: initialValue.time == nil)
        _draftNote = State(initialValue: initialValue.note ?? "")
        self.entryID = initialValue.id
        self.travelContext = initialValue.travelContext
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
                    .tint(editorAccent)
                    .disabled(!isEditable)
                    .padding(.horizontal, 4)

                if !logsExistenceOnly {
                    timeEditor
                }

                RecordNoteSection(note: $draftNote, surface: editorSurface)
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
        .background(editorBackground.ignoresSafeArea())
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
                    .foregroundStyle(editorAccent)

                Spacer()

                Button(NSLocalizedString("保存", comment: "")) {
                    onSave(
                        BowelMovementEntry(
                            id: entryID,
                            time: logsExistenceOnly ? nil : normalizedTime,
                            timeZoneIdentifier: logsExistenceOnly ? nil : phoneTimeZone.identifier,
                            note: draftNote,
                            travelContext: travelContext
                        )
                    )
                    dismiss()
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(editorAccent)
                .disabled(!isEditable)
            }
        }
    }

    private var timeEditor: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                if isTravelModeEditor {
                    HStack {
                        Spacer()
                        phoneTimeBadge
                    }
                }

                Text(appViewModel.displayedClockTime(
                    for: normalizedTime,
                    recordedTimeZoneIdentifier: nil
                ))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(editorAccent)
                    .monospacedDigit()
            }

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
            .environment(\.timeZone, phoneTimeZone)
        }
        .frame(maxWidth: .infinity)
    }

    private var normalizedTime: Date {
        appViewModel.normalizedEventTimestamp(
            from: draftTime,
            baseDate: baseDate,
            recordedTimeZoneIdentifier: nil
        )
    }

    private var effectiveTravelContext: TravelRecordContext? {
        travelContext ?? appViewModel.travelContextForCurrentRecording()
    }

    private var isTravelModeEditor: Bool {
        effectiveTravelContext != nil
    }

    private var editorBackground: Color {
        isTravelModeEditor ? AppTheme.travelBackground : AppTheme.background
    }

    private var editorSurface: Color {
        isTravelModeEditor ? AppTheme.travelSurface : AppTheme.elevatedSurface
    }

    private var editorAccent: Color {
        isTravelModeEditor ? AppTheme.travelAccent : AppTheme.bowelAccent
    }

    private var phoneTimeZone: TimeZone {
        .autoupdatingCurrent
    }

    private var phoneTimeBadge: some View {
        Text(NSLocalizedString("手机", comment: ""))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(editorAccent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(editorAccent.opacity(0.12))
            .clipShape(Capsule())
    }
}
