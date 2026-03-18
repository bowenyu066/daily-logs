import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingTargetBedtime = false
    @State private var showingMealSlots = false
    @State private var isEditingNickname = false
    @State private var nicknameText = ""
    @State private var showingHomeSections = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        accountCard
                        preferenceCard
                        cloudEncryptionCard
                        homeSectionsCard
                        defaultMealsCard
                        healthKitCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(NSLocalizedString("设置", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTargetBedtime) {
                TargetBedtimeSheet(initialValue: appViewModel.preferences.bedtimeSchedule) { schedule in
                    Task { await appViewModel.updateBedtimeSchedule(schedule) }
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingHomeSections) {
                HomeSectionCustomizationView()
                    .environmentObject(appViewModel)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingMealSlots) {
                DefaultMealSlotsSheet()
                    .environmentObject(appViewModel)
                    .presentationDetents([.fraction(0.34), .medium])
                    .presentationDragIndicator(.visible)
            }
            .alert(NSLocalizedString("修改昵称", comment: ""), isPresented: $isEditingNickname) {
                TextField(NSLocalizedString("昵称", comment: ""), text: $nicknameText)
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("确定", comment: "")) {
                    let trimmed = nicknameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await appViewModel.updateDisplayName(trimmed) }
                }
            } message: {
                Text(NSLocalizedString("输入你想使用的昵称", comment: ""))
            }
            .alert(NSLocalizedString("提示", comment: ""), isPresented: .constant(appViewModel.errorMessage != nil && !appViewModel.isCloudMigrationInProgress)) {
                Button(NSLocalizedString("知道了", comment: "")) {
                    appViewModel.errorMessage = nil
                }
            } message: {
                Text(appViewModel.errorMessage ?? "")
            }
            .task(id: appViewModel.user?.userID) {
                await appViewModel.refreshCloudEncryptionState()
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: NSLocalizedString("账号", comment: ""), subtitle: nil)
            HStack(spacing: 14) {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(String(appViewModel.user?.displayName.prefix(1) ?? NSLocalizedString("我", comment: "").prefix(1)))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    )
                    .overlay(
                        Circle()
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(appViewModel.user?.displayName ?? NSLocalizedString("未登录", comment: ""))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Button {
                            nicknameText = appViewModel.user?.displayName ?? ""
                            isEditingNickname = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(accountSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
            }

            Button(accountActionTitle) {
                Task { await appViewModel.signOut() }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(appViewModel.user?.isGuest == true ? AppTheme.secondaryText.opacity(0.35) : AppTheme.actionFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(22)
        .appCardStyle()
    }

    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: NSLocalizedString("偏好", comment: ""), subtitle: nil)
            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        Task { await appViewModel.updateAppearanceMode(mode) }
                    } label: {
                        HStack {
                            Text(mode.title)
                            if appViewModel.preferences.appearanceMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SettingsStaticRow(title: NSLocalizedString("外观", comment: ""), value: appViewModel.preferences.appearanceMode.title)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        Task { await appViewModel.updateAppLanguage(lang) }
                    } label: {
                        HStack {
                            Text(lang.title)
                            if appViewModel.preferences.appLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                SettingsStaticRow(title: NSLocalizedString("语言", comment: ""), value: appViewModel.preferences.appLanguage.title)
            }
            .buttonStyle(.plain)

            SettingsRow(title: NSLocalizedString("目标入睡", comment: ""), value: appViewModel.bedtimeScheduleSummary()) {
                showingTargetBedtime = true
            }

            timeDisplayModeSection

            LocationPermissionToggleRow(
                isOn: Binding(
                    get: { appViewModel.preferences.locationPermissionState == .authorized },
                    set: { isOn in
                        if isOn {
                            appViewModel.requestLocationAccess()
                        } else if appViewModel.preferences.locationPermissionState == .authorized {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                )
            )
        }
        .padding(22)
        .appCardStyle()
    }

    private var cloudEncryptionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: NSLocalizedString("云端加密", comment: ""),
                subtitle: NSLocalizedString("开启加密后，所有数据将完全以加密方式安全存储在云端。", comment: "")
            )

            if !cloudEncryptionDescription.isEmpty {
                Text(cloudEncryptionDescription)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(cloudEncryptionAccent)
                    .frame(width: 10, height: 10)
                Text(cloudEncryptionTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }

            if appViewModel.user?.isGuest == true {
                Text(NSLocalizedString("游客模式不使用云同步。", comment: ""))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                actionButtons
            }
        }
        .padding(22)
        .appCardStyle()
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch appViewModel.cloudEncryptionState {
        case .unavailable:
            Text(NSLocalizedString("当前设备未启用云同步。", comment: ""))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
        case .disabled:
            primaryActionButton(
                title: NSLocalizedString("立即升级为端到端加密", comment: ""),
                action: { appViewModel.shouldPresentCloudMigration = true }
            )
        case .locked:
            VStack(spacing: 10) {
                secondaryActionButton(
                    title: NSLocalizedString("重新检查同步密钥", comment: ""),
                    action: {
                        Task { await appViewModel.refreshCloudEncryptionState() }
                    }
                )
            }
        case .unlocked:
            primaryActionButton(
                title: NSLocalizedString("这台设备已受端到端加密保护", comment: ""),
                action: {}
            )
            .disabled(true)
        }
    }

    private func primaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.actionFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var cloudEncryptionTitle: String {
        switch appViewModel.cloudEncryptionState {
        case .unavailable:
            return NSLocalizedString("云同步不可用", comment: "")
        case .disabled:
            return NSLocalizedString("当前仍是普通云同步", comment: "")
        case .locked:
            return NSLocalizedString("这台设备还没拿到密钥", comment: "")
        case .unlocked:
            return NSLocalizedString("端到端加密已开启", comment: "")
        }
    }

    private var cloudEncryptionDescription: String {
        switch appViewModel.cloudEncryptionState {
        case .unavailable:
            return NSLocalizedString("未检测到云同步。", comment: "")
        case .disabled:
            return NSLocalizedString("开启后，数据会先在设备加密，再上传云端。", comment: "")
        case .locked:
            return NSLocalizedString("请检查同一 Apple ID 和 iCloud 钥匙串。", comment: "")
        case .unlocked:
            return ""
        }
    }

    private var cloudEncryptionAccent: Color {
        switch appViewModel.cloudEncryptionState {
        case .unavailable:
            return AppTheme.secondaryText.opacity(0.4)
        case .disabled:
            return AppTheme.warning
        case .locked:
            return AppTheme.warning
        case .unlocked:
            return AppTheme.accent
        }
    }

    private var timeDisplayModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("时间展示方式", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Text(NSLocalizedString("默认使用记录地原始时间，跨时区后回看旧记录时，仍保持记录当时的本地钟点。", comment: ""))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                timeDisplayModeRow(
                    mode: .recorded,
                    title: NSLocalizedString("展示页全部使用记录地原始时间", comment: ""),
                    subtitle: NSLocalizedString("默认使用原始时间；跨时区后仍显示记录当时的本地时间。", comment: "")
                )

                timeDisplayModeRow(
                    mode: .current,
                    title: NSLocalizedString("展示页使用绝对时间", comment: ""),
                    subtitle: NSLocalizedString("按你当前所在时区换算显示同一时刻。", comment: "")
                )
            }
        }
    }

    private func timeDisplayModeRow(mode: TimeDisplayMode, title: String, subtitle: String) -> some View {
        Button {
            Task { await appViewModel.updateTimeDisplayMode(mode) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: appViewModel.preferences.timeDisplayMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(appViewModel.preferences.timeDisplayMode == mode ? AppTheme.accent : AppTheme.secondaryText.opacity(0.5))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        appViewModel.preferences.timeDisplayMode == mode ? AppTheme.accent.opacity(0.35) : AppTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var defaultMealsCard: some View {
        Button {
            showingMealSlots = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(NSLocalizedString("默认餐次", comment: ""))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appViewModel.preferences.defaultMealSlots) { slot in
                            Text(slot.displayTitle)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(AppTheme.surface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(18)
        .appCardStyle()
    }

    private var healthKitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: NSLocalizedString("Apple Health 睡眠", comment: ""), subtitle: nil)
            Text(NSLocalizedString("自动从 Apple Health 同步睡眠数据（含阶段），替代手动输入。", comment: ""))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            HStack {
                Text(NSLocalizedString("HealthKit 同步", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appViewModel.preferences.healthKitSyncEnabled },
                    set: { enabled in
                        Task { await appViewModel.toggleHealthKitSync(enabled) }
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.accent)
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private var homeSectionsCard: some View {
        Button {
            showingHomeSections = true
        } label: {
            HStack {
                Text(NSLocalizedString("自定义首页", comment: ""))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .padding(22)
        .appCardStyle()
    }

    private var accountSubtitle: String {
        if appViewModel.user?.isGuest == true {
            return NSLocalizedString("游客模式，本地保存", comment: "")
        }
        return appViewModel.user?.email ?? NSLocalizedString("Apple 登录", comment: "")
    }

    private var accountActionTitle: String {
        appViewModel.user?.isGuest == true ? NSLocalizedString("结束游客模式", comment: "") : NSLocalizedString("退出登录", comment: "")
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsStaticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}

private struct LocationPermissionToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(NSLocalizedString("位置权限", comment: ""))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
        }
        .padding(.vertical, 2)
    }
}

struct HomeSectionCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(HomeSectionKind.allCases) { section in
                    HStack {
                        Text(section.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appViewModel.preferences.visibleHomeSections.contains(section) },
                            set: { isOn in
                                var sections = appViewModel.preferences.visibleHomeSections
                                if isOn {
                                    if !sections.contains(section) {
                                        sections.append(section)
                                    }
                                } else {
                                    sections.removeAll { $0 == section }
                                }
                                Task { await appViewModel.updateVisibleHomeSections(sections) }
                            }
                        ))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                    }
                    .listRowBackground(AppTheme.surface)
                }

                if appViewModel.preferences.visibleHomeSections.contains(.sexualActivity) {
                    Section {
                        HStack {
                            Text(NSLocalizedString("显示自慰选项", comment: ""))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appViewModel.preferences.showMasturbationOption },
                                set: { enabled in
                                    Task { await appViewModel.updateShowMasturbationOption(enabled) }
                                }
                            ))
                            .labelsHidden()
                            .tint(.pink)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("自定义首页", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("完成", comment: "")) { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationBackground(AppTheme.background)
    }
}
