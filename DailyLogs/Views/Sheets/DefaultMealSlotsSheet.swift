import SwiftUI

struct DefaultMealSlotsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var title = ""

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10, alignment: .leading)]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(appViewModel.preferences.defaultMealSlots) { slot in
                        MealSlotChip(
                            title: slot.title,
                            isLocked: slot.isDefault,
                            onDelete: slot.isDefault ? nil : {
                                Task { await appViewModel.deleteDefaultMealSlot(slot) }
                            }
                        )
                    }
                }

                HStack(spacing: 10) {
                    TextField("夜宵", text: $title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )

                    Button("添加") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { await appViewModel.addDefaultMealSlot(title: trimmed) }
                        title = ""
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.secondaryText.opacity(0.35) : AppTheme.accent)
                    .clipShape(Capsule())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("默认餐次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

private struct MealSlotChip: View {
    let title: String
    let isLocked: Bool
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            if let onDelete, !isLocked {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isLocked ? AppTheme.accentSoft : Color.white)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isLocked ? AppTheme.accentSoft : AppTheme.border, lineWidth: 1)
        )
    }
}
