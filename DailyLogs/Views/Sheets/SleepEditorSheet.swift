import SwiftUI

struct SleepEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bedtime: Date
    @State private var wakeTime: Date
    @State private var hasBedtime: Bool
    @State private var hasWakeTime: Bool
    let onSave: (Date?, Date?) -> Void

    init(record: SleepRecord, baseDate: Date, onSave: @escaping (Date?, Date?) -> Void) {
        let defaultBedtime = record.bedtimePreviousNight ?? baseDate.adding(days: -1).settingTime(hour: 23, minute: 30)
        let defaultWakeTime = record.wakeTimeCurrentDay ?? baseDate.settingTime(hour: 7, minute: 30)
        _bedtime = State(initialValue: defaultBedtime)
        _wakeTime = State(initialValue: defaultWakeTime)
        _hasBedtime = State(initialValue: record.bedtimePreviousNight != nil)
        _hasWakeTime = State(initialValue: record.wakeTimeCurrentDay != nil)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("前一晚入睡") {
                    Toggle("已记录入睡时间", isOn: $hasBedtime)
                    if hasBedtime {
                        DatePicker("入睡时间", selection: $bedtime)
                    }
                }

                Section("当天起床") {
                    Toggle("已记录起床时间", isOn: $hasWakeTime)
                    if hasWakeTime {
                        DatePicker("起床时间", selection: $wakeTime)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("编辑睡眠")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(hasBedtime ? bedtime : nil, hasWakeTime ? wakeTime : nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

