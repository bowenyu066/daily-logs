import SwiftUI
import UIKit

struct CloudEncryptionPassphraseSheet: View {
    enum Mode {
        case migration
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    let mode: Mode
    var isDismissable: Bool = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Text(message)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if appViewModel.isCloudMigrationInProgress {
                            VStack(alignment: .leading, spacing: 12) {
                                ProgressView(value: appViewModel.cloudMigrationProgress)
                                    .progressViewStyle(.linear)
                                    .tint(AppTheme.accent)

                                HStack {
                                    Text(appViewModel.cloudMigrationMessage ?? NSLocalizedString("正在迁移…", comment: ""))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.primaryText)
                                    Spacer()
                                    Text(progressText)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .padding(18)
                            .background(AppTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        if let migrationError = appViewModel.cloudMigrationError {
                            Text(migrationError)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button(actionTitle) {
                            submit()
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.actionFill)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .disabled(appViewModel.isCloudMigrationInProgress)

                        Text(NSLocalizedString("只需迁移一次。其他设备会通过 iCloud 钥匙串自动拿到密钥。", comment: ""))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isDismissable && !appViewModel.isCloudMigrationInProgress {
                        Button(NSLocalizedString("取消", comment: "")) {
                            dismiss()
                        }
                    }
                }
            }
            .onChange(of: appViewModel.shouldPresentCloudMigration) { _, isPresented in
                if !isPresented {
                    dismiss()
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .migration:
            return NSLocalizedString("云端隐私升级", comment: "")
        }
    }

    private var message: String {
        switch mode {
        case .migration:
            return NSLocalizedString("检测到旧版云数据，需要升级到加密存储。", comment: "")
        }
    }

    private var actionTitle: String {
        switch mode {
        case .migration:
            return appViewModel.cloudMigrationError == nil
                ? NSLocalizedString("开始升级", comment: "")
                : NSLocalizedString("重试升级", comment: "")
        }
    }

    private var progressText: String {
        "\(Int((appViewModel.cloudMigrationProgress * 100).rounded()))%"
    }

    private func submit() {
        switch mode {
        case .migration:
            Task {
                await appViewModel.beginAutomaticCloudMigration()
            }
        }
    }
}

/// Creates a recovery code on a device that has the encryption key, or unlocks a device that does
/// not with a code created earlier.
struct CloudRecoveryCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    let mode: AppViewModel.CloudRecoverySheet

    @State private var generatedCode: String?
    @State private var enteredCode = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(mode == .create
                            ? NSLocalizedString("应急恢复密钥", comment: "")
                            : NSLocalizedString("输入应急恢复密钥", comment: ""))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        switch mode {
                        case .create:
                            createContent
                        case .unlock:
                            unlockContent
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(generatedCode == nil ? NSLocalizedString("取消", comment: "") : NSLocalizedString("完成", comment: "")) {
                        dismiss()
                    }
                    .disabled(isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    @ViewBuilder
    private var createContent: some View {
        if let generatedCode {
            Text(NSLocalizedString("请妥善保存这串密钥，它只会显示这一次。", comment: ""))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(generatedCode)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            actionButton(didCopy ? NSLocalizedString("已复制", comment: "") : NSLocalizedString("复制密钥", comment: "")) {
                UIPasteboard.general.string = generatedCode
                didCopy = true
            }
        } else {
            Text(NSLocalizedString("应急恢复密钥可帮助您在云端数据无法正常同步时重置密钥。", comment: ""))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if appViewModel.hasCloudRecoveryCode {
                Text(NSLocalizedString("重新设置后，之前的应急恢复密钥将失效。", comment: ""))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.warning)
            }

            actionButton(NSLocalizedString("设置应急恢复密钥", comment: "")) {
                Task { await createCode() }
            }
        }
    }

    @ViewBuilder
    private var unlockContent: some View {
        Text(NSLocalizedString("请输入您之前保存的应急恢复密钥。", comment: ""))
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        TextField(NSLocalizedString("应急恢复密钥", comment: ""), text: $enteredCode, axis: .vertical)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            // A Latin keyboard: a Chinese input method would hold the letters as pinyin candidates.
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(16)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        actionButton(NSLocalizedString("确认", comment: "")) {
            Task { await unlock() }
        }
        .disabled(enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.actionFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func createCode() async {
        isWorking = true
        errorText = nil
        do {
            generatedCode = try await appViewModel.createCloudRecoveryCode()
        } catch {
            errorText = NSLocalizedString("生成失败：", comment: "") + error.localizedDescription
        }
        isWorking = false
    }

    private func unlock() async {
        isWorking = true
        errorText = nil
        do {
            try await appViewModel.unlockCloudSync(withRecoveryCode: enteredCode)
            isWorking = false
            dismiss()
        } catch {
            isWorking = false
            errorText = error.localizedDescription
        }
    }
}
