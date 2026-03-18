import SwiftUI

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

                        Text(NSLocalizedString("迁移只需要做一次。完成后，记录、备注、时间和图片都会先在设备上加密，再上传到云端；如果你的其他设备开启了 iCloud 钥匙串，会自动拿到同一把密钥。", comment: ""))
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
            return NSLocalizedString("你之前版本的云同步仍是旧的明文存储方式。这次升级会自动把历史云端数据迁移到新的端到端加密存储，并在迁移过程中实时显示进度。", comment: "")
        }
    }

    private var actionTitle: String {
        switch mode {
        case .migration:
            return appViewModel.cloudMigrationError == nil
                ? NSLocalizedString("开始自动迁移", comment: "")
                : NSLocalizedString("重新尝试迁移", comment: "")
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
