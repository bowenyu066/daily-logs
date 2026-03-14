import SwiftUI

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftDate: Date
    let allowedRange: ClosedRange<Date>
    let onConfirm: (Date) -> Void

    init(selectedDate: Date, allowedRange: ClosedRange<Date>, onConfirm: @escaping (Date) -> Void) {
        _draftDate = State(initialValue: selectedDate)
        self.allowedRange = allowedRange
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("选择日期", selection: $draftDate, in: allowedRange, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                Spacer()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(draftDate)
                        dismiss()
                    }
                }
            }
        }
    }
}
