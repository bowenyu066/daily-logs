import SwiftUI

struct SexualActivityEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var dateOnly: Bool
    @State private var draftTime: Date
    @State private var isMasturbation: Bool
    @State private var draftNote: String
    @State private var showingDeleteConfirmation = false

    let baseDate: Date
    let isEditable: Bool
    let onSave: (SexualActivityEntry) -> Void
    let onDelete: (() -> Void)?

    private let entryID: UUID
    private let travelContext: TravelRecordContext?

    init(
        initialValue: SexualActivityEntry,
        baseDate: Date,
        fallbackTime: Date,
        isEditable: Bool,
        onSave: @escaping (SexualActivityEntry) -> Void,
        onDelete: (() -> Void)?
    ) {
        _dateOnly = State(initialValue: initialValue.time == nil)
        _draftTime = State(initialValue: initialValue.time ?? fallbackTime)
        _isMasturbation = State(initialValue: initialValue.isMasturbation)
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

                Toggle(NSLocalizedString("仅记录有/无", comment: ""), isOn: $dateOnly)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(editorAccent)
                    .disabled(!isEditable)
                    .padding(.horizontal, 4)

                if !dateOnly {
                    timeEditor
                }

                if appViewModel.preferences.showMasturbationOption {
                    Toggle(NSLocalizedString("自慰", comment: ""), isOn: $isMasturbation)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .tint(editorAccent)
                        .disabled(!isEditable)
                        .padding(.horizontal, 4)
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
            Text(NSLocalizedString("性生活", comment: ""))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(editorAccent)

                Spacer()

                Button(NSLocalizedString("保存", comment: "")) {
                    let resolvedTime: Date? = dateOnly ? nil : normalizedTime
                    onSave(
                        SexualActivityEntry(
                            id: entryID,
                            date: baseDate,
                            time: resolvedTime,
                            isMasturbation: appViewModel.preferences.showMasturbationOption ? isMasturbation : false,
                            timeZoneIdentifier: resolvedTime != nil ? phoneTimeZone.identifier : nil,
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
            recordedTimeZoneIdentifier: nil,
            travelContext: effectiveTravelContext
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
        isTravelModeEditor ? AppTheme.travelAccent : AppTheme.sexualAccent
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
