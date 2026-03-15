import SwiftUI

struct DefaultMealSlotsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar
                .padding(.top, 26)

            TagFlowLayout(spacing: 8, lineSpacing: 10) {
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
                TextField(String(localized: "夜宵"), text: $title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                Button(String(localized: "添加")) {
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await appViewModel.addDefaultMealSlot(title: trimmed) }
                    title = ""
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.secondaryText.opacity(0.35) : AppTheme.accent)
                .clipShape(Capsule())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var headerBar: some View {
        ZStack {
            Text(String(localized: "默认餐次"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Button(String(localized: "完成")) { dismiss() }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
            }
        }
    }
}

private struct MealSlotChip: View {
    let title: String
    let isLocked: Bool
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if let onDelete, !isLocked {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isLocked ? AppTheme.accentSoft : AppTheme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isLocked ? AppTheme.accentSoft : AppTheme.border, lineWidth: 1)
        )
    }
}

private struct TagFlowLayout<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: Content

    init(
        spacing: CGFloat,
        lineSpacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        FlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat, lineSpacing: CGFloat) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
