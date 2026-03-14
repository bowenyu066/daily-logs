import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingTargetBedtime = false
    @State private var showingAddMealSlot = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        accountCard
                        preferenceCard
                        defaultMealsCard
                        syncPlaceholderCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTargetBedtime) {
                TargetBedtimeSheet(initialValue: appViewModel.preferences.bedtimeSchedule) { schedule in
                    Task { await appViewModel.updateBedtimeSchedule(schedule) }
                }
            }
            .sheet(isPresented: $showingAddMealSlot) {
                AddCustomMealSlotSheet { title in
                    Task { await appViewModel.addDefaultMealSlot(title: title) }
                }
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "账号", subtitle: nil)
            HStack(spacing: 14) {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(String(appViewModel.user?.displayName.prefix(1) ?? "我"))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(appViewModel.user?.displayName ?? "未登录")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(accountSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
            }

            Button("退出登录") {
                Task { await appViewModel.signOut() }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(22)
        .appCardStyle()
    }

    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "偏好", subtitle: nil)
            SettingsRow(title: "目标入睡", value: appViewModel.bedtimeScheduleSummary()) {
                showingTargetBedtime = true
            }
            SettingsRow(title: "位置权限", value: permissionText) {
                appViewModel.requestLocationAccess()
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private var defaultMealsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "默认餐次",
                subtitle: nil,
                actionTitle: "添加"
            ) {
                showingAddMealSlot = true
            }

            ForEach(appViewModel.preferences.defaultMealSlots) { slot in
                HStack {
                    Text(slot.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    if slot.isDefault {
                        Text("默认")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.accentSoft)
                            .clipShape(Capsule())
                    } else {
                        Button("删除") {
                            Task { await appViewModel.deleteDefaultMealSlot(slot) }
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.warning)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private var syncPlaceholderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "同步", subtitle: nil)
            HStack {
                Text("Apple Watch")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text("稍后")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private var permissionText: String {
        switch appViewModel.preferences.locationPermissionState {
        case .authorized: "已开启"
        case .denied: "已拒绝"
        case .notDetermined: "未设置"
        }
    }

    private var accountSubtitle: String {
        if appViewModel.user?.isGuest == true {
            return "游客模式，本地保存"
        }
        return appViewModel.user?.email ?? "Apple 登录"
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
