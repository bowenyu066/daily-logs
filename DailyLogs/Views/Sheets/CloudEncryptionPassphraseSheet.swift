import SwiftUI

struct CloudEncryptionPassphraseSheet: View {
    enum Mode {
        case enable
        case unlock
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel
    @FocusState private var focusedField: Field?

    @State private var passphrase = ""
    @State private var confirmation = ""

    let mode: Mode
    var isDismissable: Bool = true

    private enum Field {
        case passphrase
        case confirmation
    }

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

                        secureField(
                            title: NSLocalizedString("同步密码", comment: ""),
                            text: $passphrase,
                            field: .passphrase
                        )

                        if mode == .enable {
                            secureField(
                                title: NSLocalizedString("再次输入同步密码", comment: ""),
                                text: $confirmation,
                                field: .confirmation
                            )
                        }

                        if mode == .enable {
                            Text(NSLocalizedString("这个密码不会上传到服务器。你在新设备登录同一账号时，需要靠它来解锁云端数据；如果忘记，云端加密数据将无法恢复。", comment: ""))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
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
                        .disabled(!canSubmit)
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isDismissable {
                        Button(NSLocalizedString("取消", comment: "")) {
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("完成", comment: "")) {
                        focusedField = nil
                    }
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .enable:
            return NSLocalizedString("启用加密同步", comment: "")
        case .unlock:
            return NSLocalizedString("解锁加密同步", comment: "")
        }
    }

    private var message: String {
        switch mode {
        case .enable:
            return NSLocalizedString("启用后，记录、备注、时间、图片都会先在设备上加密，再上传到云端。项目 owner 只能看到密文，不能直接看到用户内容。", comment: "")
        case .unlock:
            return NSLocalizedString("这台设备还没有保存同步密钥。输入之前设置的同步密码后，才能拉取和同步云端加密数据。", comment: "")
        }
    }

    private var actionTitle: String {
        switch mode {
        case .enable:
            return NSLocalizedString("开始加密迁移", comment: "")
        case .unlock:
            return NSLocalizedString("解锁并同步", comment: "")
        }
    }

    private var canSubmit: Bool {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch mode {
        case .enable:
            return trimmed == confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        case .unlock:
            return true
        }
    }

    private func secureField(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            SecureField(title, text: text)
                .textContentType(.password)
                .focused($focusedField, equals: field)
                .submitLabel(mode == .enable && field == .passphrase ? .next : .done)
                .onSubmit {
                    if mode == .enable && field == .passphrase {
                        focusedField = .confirmation
                    } else {
                        focusedField = nil
                    }
                }
                .font(.system(size: 16, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func submit() {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .enable:
            Task {
                await appViewModel.enableEndToEndEncryption(passphrase: trimmed)
                if appViewModel.cloudEncryptionState == .unlocked {
                    dismiss()
                }
            }
        case .unlock:
            Task {
                await appViewModel.unlockEndToEndEncryption(passphrase: trimmed)
                if appViewModel.cloudEncryptionState == .unlocked {
                    dismiss()
                }
            }
        }
    }
}
