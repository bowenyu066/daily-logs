import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingDatePicker = false
    @State private var showingSleepEditor = false
    @State private var showingTargetBedtime = false
    @State private var editingMealContext: MealEditorContext?
    @State private var editingShower: ShowerEntry?
    @State private var showingNewShower = false

    private let mealColumns = [GridItem(.adaptive(minimum: 156), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        sleepSection
                        mealSection
                        showerSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(
                    selectedDate: appViewModel.selectedDate,
                    allowedRange: appViewModel.availableDateRange
                ) { date in
                    Task { await appViewModel.selectDate(date) }
                }
            }
            .sheet(isPresented: $showingSleepEditor) {
                SleepEditorSheet(record: appViewModel.dailyRecord.sleepRecord, baseDate: appViewModel.selectedDate) { bedtime, wakeTime in
                    Task { await appViewModel.updateSleep(bedtime: bedtime, wakeTime: wakeTime) }
                }
            }
            .sheet(isPresented: $showingTargetBedtime) {
                TargetBedtimeSheet(initialValue: appViewModel.preferences.bedtimeSchedule) { schedule in
                    Task { await appViewModel.updateBedtimeSchedule(schedule) }
                }
            }
            .sheet(item: $editingMealContext) { context in
                MealEditorSheet(
                    entry: context.entry,
                    baseDate: appViewModel.selectedDate,
                    preferredSource: context.preferredSource,
                    canDelete: context.entry.mealKind == .custom,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated, image in
                        Task { await appViewModel.saveMeal(updated, image: image) }
                    },
                    onDelete: {
                        Task { await appViewModel.deleteMeal(context.entry) }
                    }
                )
            }
            .sheet(item: $editingShower) { shower in
                ShowerEditorSheet(
                    initialValue: shower,
                    baseDate: appViewModel.selectedDate,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated in
                        Task { await appViewModel.saveShower(updated) }
                    },
                    onDelete: {
                        Task { await appViewModel.deleteShower(shower) }
                    }
                )
            }
            .sheet(isPresented: $showingNewShower) {
                ShowerEditorSheet(
                    initialValue: ShowerEntry(time: appViewModel.selectedDate.settingTime(hour: 21, minute: 30)),
                    baseDate: appViewModel.selectedDate,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated in
                        Task { await appViewModel.saveShower(updated) }
                    },
                    onDelete: nil
                )
            }
            .alert("提示", isPresented: .constant(appViewModel.errorMessage != nil), actions: {
                Button("知道了") {
                    appViewModel.errorMessage = nil
                }
            }, message: {
                Text(appViewModel.errorMessage ?? "")
            })
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Calendar.current.isDateInToday(appViewModel.selectedDate) ? "今天是" : "这一天")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    Button {
                        showingDatePicker = true
                    } label: {
                        Text(appViewModel.selectedDate.formattedDayTitle())
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    if appViewModel.dailyRecord.sunTimes == nil {
                        appViewModel.requestLocationAccess()
                    } else {
                        showingDatePicker = true
                    }
                } label: {
                    Image(systemName: appViewModel.dailyRecord.sunTimes == nil ? "location" : "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                SunMetricCard(title: "日出", icon: "sunrise", value: formattedSun(appViewModel.dailyRecord.sunTimes?.sunrise))
                SunMetricCard(title: "日落", icon: "sunset", value: formattedSun(appViewModel.dailyRecord.sunTimes?.sunset))
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("睡眠")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Button {
                    showingTargetBedtime = true
                } label: {
                    Text("目标入睡：\(appViewModel.formattedTargetBedtime())")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 14) {
                Button {
                    showingSleepEditor = true
                } label: {
                    HStack(spacing: 14) {
                        SleepMetricCard(
                            title: "入睡",
                            value: appViewModel.dailyRecord.sleepRecord.bedtimePreviousNight?.displayClockTime,
                            accent: .purple
                        )

                        SleepMetricCard(
                            title: "起床",
                            value: appViewModel.dailyRecord.sleepRecord.wakeTimeCurrentDay?.displayClockTime,
                            accent: .purple
                        )
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Text("总睡眠时长")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Text(durationText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(durationText == "无记录" ? AppTheme.secondaryText : AppTheme.primaryText)
                }
                .padding(.horizontal, 6)
            }
            .padding(18)
            .appCardStyle()
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "餐食", subtitle: nil)

            LazyVGrid(columns: mealColumns, spacing: 14) {
                ForEach(appViewModel.dailyRecord.meals) { meal in
                    Menu {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("拍照") {
                                openMealEditor(meal, with: .camera)
                            }
                        }
                        Button("选择相册照片") {
                            openMealEditor(meal, with: .photoLibrary)
                        }
                        Button("仅记录时间") {
                            openMealEditor(meal, with: .timeOnly)
                        }
                        Button("跳过", role: .destructive) {
                            Task { await appViewModel.skipMeal(meal) }
                        }
                    } label: {
                        MealCard(entry: meal, recordDate: appViewModel.selectedDate)
                    }
                    .buttonStyle(.plain)
                    .disabled(!appViewModel.canEditSelectedDate)
                }

                Button {
                    editingMealContext = MealEditorContext(
                        entry: MealEntry(
                        mealKind: .custom,
                        customTitle: "加餐",
                        status: .logged,
                        time: appViewModel.selectedDate.settingTime(hour: 15, minute: 0),
                        photoURL: nil
                    )
                        ,
                        preferredSource: .timeOnly
                    )
                } label: {
                    AddMealCard()
                }
                .buttonStyle(.plain)
                .disabled(!appViewModel.canEditSelectedDate)
                .opacity(appViewModel.canEditSelectedDate ? 1 : 0.45)
            }
        }
    }

    private var showerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "洗澡",
                subtitle: nil,
                actionTitle: appViewModel.canEditSelectedDate ? "添加" : nil
            ) {
                showingNewShower = true
            }

            VStack(spacing: 10) {
                if appViewModel.dailyRecord.showers.isEmpty {
                    HStack {
                        Spacer()
                        Text("无记录")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.54))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ForEach(appViewModel.dailyRecord.showers) { shower in
                        Button {
                            editingShower = shower
                        } label: {
                            HStack {
                                Text(shower.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .appCardStyle()
        }
    }

    private var durationText: String {
        guard let duration = appViewModel.dailyRecord.sleepRecord.duration else {
            return "无记录"
        }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return "\(hours)小时\(minutes)分"
    }

    private func formattedSun(_ date: Date?) -> String {
        date?.displayClockTime ?? "--:--"
    }

    private func openMealEditor(_ meal: MealEntry, with source: MealCaptureMode) {
        DispatchQueue.main.async {
            editingMealContext = MealEditorContext(entry: meal, preferredSource: source)
        }
    }
}

struct MealEditorContext: Identifiable {
    let entry: MealEntry
    let preferredSource: MealCaptureMode

    var id: UUID { entry.id }
}

private struct SunMetricCard: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SleepMetricCard: View {
    let title: String
    let value: String?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            if let value {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            } else {
                Text("无记录")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MealCard: View {
    let entry: MealEntry
    let recordDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.displayTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                if thumbnailImage != nil {
                    Image(systemName: "photo")
                        .foregroundStyle(AppTheme.accent)
                }
            }

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if effectiveStatus == .logged {
                            Text(bottomText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.42))
                                .clipShape(Capsule())
                                .padding(10)
                        }
                    }
            } else {
                Spacer(minLength: 0)

                Text(bottomText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(18)
        .frame(minHeight: 132, alignment: .topLeading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(effectiveStatus == .skipped ? AppTheme.warning.opacity(0.35) : AppTheme.border, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow.opacity(0.7), radius: 16, x: 0, y: 10)
    }

    private var bottomText: String {
        switch effectiveStatus {
        case .empty:
            return "无记录"
        case .logged:
            return entry.time?.displayClockTime ?? "无记录"
        case .skipped:
            return "跳过"
        }
    }

    private var statusColor: Color {
        switch effectiveStatus {
        case .empty: AppTheme.secondaryText
        case .logged: AppTheme.primaryText
        case .skipped: AppTheme.warning
        }
    }

    private var backgroundColor: Color {
        switch effectiveStatus {
        case .empty: Color.white.opacity(0.84)
        case .logged: AppTheme.accentSoft.opacity(0.92)
        case .skipped: AppTheme.warning.opacity(0.12)
        }
    }

    private var thumbnailImage: UIImage? {
        guard let photoURL = entry.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL)
    }

    private var effectiveStatus: MealStatus {
        entry.effectiveStatus(on: recordDate)
    }
}

private struct AddMealCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppTheme.secondaryText)
            Text("添加")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
        }
        .frame(minHeight: 132)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .foregroundStyle(AppTheme.accent.opacity(0.5))
        )
    }
}
