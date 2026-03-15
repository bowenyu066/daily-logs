import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingTargetBedtime = false
    @State private var showingMealSlots = false
    @State private var isEditingNickname = false
    @State private var nicknameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        accountCard
                        preferenceCard
                        defaultMealsCard
                        healthKitCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(String(localized: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTargetBedtime) {
                TargetBedtimeSheet(initialValue: appViewModel.preferences.bedtimeSchedule) { schedule in
                    Task { await appViewModel.updateBedtimeSchedule(schedule) }
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingMealSlots) {
                DefaultMealSlotsSheet()
                    .environmentObject(appViewModel)
                    .presentationDetents([.fraction(0.34), .medium])
                    .presentationDragIndicator(.visible)
            }
            .alert(String(localized: "修改昵称"), isPresented: $isEditingNickname) {
                TextField(String(localized: "昵称"), text: $nicknameText)
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "确定")) {
                    let trimmed = nicknameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await appViewModel.updateDisplayName(trimmed) }
                }
            } message: {
                Text(String(localized: "输入你想使用的昵称"))
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: String(localized: "账号"), subtitle: nil)
            HStack(spacing: 14) {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(String(appViewModel.user?.displayName.prefix(1) ?? String(localized: "我").prefix(1)))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    )
                    .overlay(
                        Circle()
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(appViewModel.user?.displayName ?? String(localized: "未登录"))
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
            SectionHeader(title: String(localized: "偏好"), subtitle: nil)
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
                SettingsStaticRow(title: String(localized: "外观"), value: appViewModel.preferences.appearanceMode.title)
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
                SettingsStaticRow(title: String(localized: "语言"), value: appViewModel.preferences.appLanguage.title)
            }
            .buttonStyle(.plain)

            SettingsRow(title: String(localized: "目标入睡"), value: appViewModel.bedtimeScheduleSummary()) {
                showingTargetBedtime = true
            }
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

    private var defaultMealsCard: some View {
        Button {
            showingMealSlots = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(localized: "默认餐次"))
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
                                .foregroundStyle(slot.isDefault ? AppTheme.accent : AppTheme.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(slot.isDefault ? AppTheme.accentSoft : AppTheme.surface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(slot.isDefault ? AppTheme.accentSoft : AppTheme.border, lineWidth: 1)
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
            SectionHeader(title: String(localized: "Apple Health 睡眠"), subtitle: nil)
            Text(String(localized: "自动从 Apple Health 同步睡眠数据（含阶段），替代手动输入。"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            HStack {
                Text(String(localized: "HealthKit 同步"))
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

    private var accountSubtitle: String {
        if appViewModel.user?.isGuest == true {
            return String(localized: "游客模式，本地保存")
        }
        return appViewModel.user?.email ?? String(localized: "Apple 登录")
    }

    private var accountActionTitle: String {
        appViewModel.user?.isGuest == true ? String(localized: "结束游客模式") : String(localized: "退出登录")
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
            Text(String(localized: "位置权限"))
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
