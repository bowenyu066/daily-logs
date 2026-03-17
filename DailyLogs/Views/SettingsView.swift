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
            .navigationTitle(NSLocalizedString("设置", comment: ""))
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
