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
    @State private var showingMidnightModeConfirmation = false
    @State private var showingMidnightModeInfoPopover = false
    @State private var pendingMidnightModeEnabled = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        accountCard
                        preferencesCard
                        dataAndSyncCard
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
                appViewModel.refreshOpenAIConfigurationState()
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 18) {
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

    // MARK: - Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(title: NSLocalizedString("偏好", comment: ""), subtitle: nil)
                .padding(.bottom, 2)

            appearanceRow
            languageRow
            bedtimeRow
            timeDisplayRow
            temperatureRow
            midnightModeRow
            locationRow
            homeSectionsRow
            defaultMealsRow
        }
        .padding(24)
        .appCardStyle()
    }

    private var appearanceRow: some View {
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
    }

    private var languageRow: some View {
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
    }

    private var bedtimeRow: some View {
        SettingsRow(title: NSLocalizedString("目标入睡", comment: ""), value: appViewModel.bedtimeScheduleSummary()) {
            showingTargetBedtime = true
        }
    }

    private var timeDisplayRow: some View {
        Menu {
            ForEach(TimeDisplayMode.allCases) { mode in
                Button {
                    Task { await appViewModel.updateTimeDisplayMode(mode) }
                } label: {
                    HStack {
                        Text(mode.title)
                        if appViewModel.preferences.timeDisplayMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            SettingsStaticRow(title: NSLocalizedString("时间展示方式", comment: ""), value: appViewModel.preferences.timeDisplayMode.title)
        }
        .buttonStyle(.plain)
    }

    private var temperatureRow: some View {
        Menu {
            ForEach(TemperatureUnitPreference.allCases) { unit in
                Button {
                    Task { await appViewModel.updateTemperatureUnit(unit) }
                } label: {
                    HStack {
                        Text(unit.title)
                        if appViewModel.preferences.temperatureUnit == unit {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            SettingsStaticRow(title: NSLocalizedString("温度单位", comment: ""), value: appViewModel.preferences.temperatureUnit.title)
        }
        .buttonStyle(.plain)
    }

    private var midnightModeRow: some View {
        HStack {
            HStack(spacing: 6) {
                Text(NSLocalizedString("午夜模式", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Button {
                    showingMidnightModeInfoPopover.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: $showingMidnightModeInfoPopover,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    midnightModeInfoPopover
                        .presentationCompactAdaptation(.popover)
                }
            }

            Spacer()
            Toggle("", isOn: Binding(
                get: { appViewModel.preferences.midnightMode.isEnabled },
                set: { isOn in
                    if isOn {
                        pendingMidnightModeEnabled = true
                        showingMidnightModeConfirmation = true
                    } else {
                        Task {
                            await appViewModel.configureMidnightMode(
                                enabled: false,
                                applyToExistingRecords: false
                            )
                        }
                    }
                }
            ))
            .labelsHidden()
            .tint(AppTheme.accent)
        }
        .padding(.vertical, 2)
        .popover(
            isPresented: $showingMidnightModeConfirmation,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            midnightModeConfirmationPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var locationRow: some View {
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

    private var homeSectionsRow: some View {
        Button {
            showingHomeSections = true
        } label: {
            HStack {
                Text(NSLocalizedString("自定义首页", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var defaultMealsRow: some View {
        Button {
            showingMealSlots = true
        } label: {
            HStack {
                Text(NSLocalizedString("默认餐次", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(mealSlotsSummary)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var mealSlotsSummary: String {
        let slots = appViewModel.preferences.defaultMealSlots
        if slots.isEmpty { return "--" }
        let count = slots.count
        let formatKey = NSLocalizedString("%d 项", comment: "")
        return String(format: formatKey, count)
    }

    // MARK: - Data & Sync

    private var dataAndSyncCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeader(title: NSLocalizedString("数据与同步", comment: ""), subtitle: nil)
                .padding(.bottom, 2)

            healthKitRow
            aiInsightsRow
            cloudEncryptionSection
        }
        .padding(24)
        .appCardStyle()
    }

    private var healthKitRow: some View {
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
        .padding(.vertical, 2)
    }

    private var aiInsightsRow: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("AI 洞察", comment: ""))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Circle()
                .fill(appViewModel.canGenerateAIInsights ? Color(red: 0.20, green: 0.63, blue: 0.60) : AppTheme.warning)
                .frame(width: 8, height: 8)
            Text(aiInsightsStatusText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var cloudEncryptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(NSLocalizedString("云端加密", comment: ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Circle()
                    .fill(cloudEncryptionAccent)
                    .frame(width: 8, height: 8)
                Text(cloudEncryptionTitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            if !cloudEncryptionDescription.isEmpty {
                Text(cloudEncryptionDescription)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appViewModel.user?.isGuest != true {
                actionButtons
            }
        }
        .padding(.vertical, 2)
    }

    private var aiInsightsStatusText: String {
        if appViewModel.isUsingCloudAIProxy {
            return NSLocalizedString("云端 AI 已连接", comment: "")
        }
        if appViewModel.user?.isGuest == true {
            return NSLocalizedString("游客模式使用本地评分", comment: "")
        }
        return NSLocalizedString("云端 AI 未就绪", comment: "")
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch appViewModel.cloudEncryptionState {
        case .unavailable:
            EmptyView()
        case .disabled:
            primaryActionButton(
                title: NSLocalizedString("立即升级为端到端加密", comment: ""),
                action: { appViewModel.shouldPresentCloudMigration = true }
            )
            .padding(.top, 6)
        case .locked:
            secondaryActionButton(
                title: NSLocalizedString("重新检查同步密钥", comment: ""),
                action: {
                    Task { await appViewModel.refreshCloudEncryptionState() }
                }
            )
            .padding(.top, 6)
        case .unlocked:
            EmptyView()
        }
    }

    private func primaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.actionFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            return Color(red: 0.20, green: 0.63, blue: 0.60)
        }
    }

    // MARK: - Midnight Mode Popovers

    private var midnightModeInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("午夜模式", comment: ""))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Text(
                NSLocalizedString("启用后，凌晨 4 点前的记录会自动归到前一天，适合经常跨零点记录。", comment: "")
            )
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .background(AppTheme.background)
    }

    private var midnightModeConfirmationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("午夜模式如何生效？", comment: ""))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Text(NSLocalizedString("凌晨截止前的记录会被算到前一天。", comment: ""))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showingMidnightModeConfirmation = false
                Task {
                    await appViewModel.configureMidnightMode(
                        enabled: pendingMidnightModeEnabled,
                        applyToExistingRecords: true
                    )
                }
            } label: {
                Text(NSLocalizedString("更新之前日期的数据", comment: ""))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                showingMidnightModeConfirmation = false
                Task {
                    await appViewModel.configureMidnightMode(
                        enabled: pendingMidnightModeEnabled,
                        applyToExistingRecords: false
                    )
                }
            } label: {
                Text(NSLocalizedString("仅从现在开始生效", comment: ""))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(NSLocalizedString("取消", comment: "")) {
                showingMidnightModeConfirmation = false
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(AppTheme.background)
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
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
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
                            .tint(AppTheme.sexualAccent)
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
