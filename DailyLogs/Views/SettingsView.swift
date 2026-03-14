import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingTargetBedtime = false
    @State private var showingMealSlots = false

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
            .sheet(isPresented: $showingMealSlots) {
                DefaultMealSlotsSheet()
                    .environmentObject(appViewModel)
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
        Button {
            showingMealSlots = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("默认餐次")
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
                            Text(slot.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(slot.isDefault ? AppTheme.accent : AppTheme.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(slot.isDefault ? AppTheme.accentSoft : Color.white)
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
