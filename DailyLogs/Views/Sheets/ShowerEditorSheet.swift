import SwiftUI

struct ShowerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShowerEntry
    let isEditable: Bool
    let onSave: (ShowerEntry) -> Void
    let onDelete: (() -> Void)?

    init(
        initialValue: ShowerEntry,
        baseDate: Date,
        isEditable: Bool,
        onSave: @escaping (ShowerEntry) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: initialValue)
        self.isEditable = isEditable
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DatePicker("洗澡时间", selection: $draft.time)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .disabled(!isEditable)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("洗澡时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isEditable)
                }
                if let onDelete {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

