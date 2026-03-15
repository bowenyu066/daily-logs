import SwiftUI

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
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
                DatePicker(NSLocalizedString("选择日期", comment: ""), selection: $draftDate, in: allowedRange, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                Spacer()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("选择日期", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("确定", comment: "")) {
                        onConfirm(draftDate)
                        dismiss()
                    }
                }
            }
        }
        .environment(\.locale, locale)
    }
}
