import SwiftUI

struct AddCustomMealSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("为未来每天预设一个新的餐次，例如加餐或夜宵。")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)

                TextField("输入餐次名称", text: $title)
                    .textFieldStyle(.roundedBorder)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("添加默认餐次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
