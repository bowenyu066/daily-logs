import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingDatePicker = false
    @State private var editingSleepTarget: SleepEditorTarget?
    @State private var showingTargetBedtime = false
    @State private var editingMealContext: MealEditorContext?
    @State private var editingShower: ShowerEntry?
    @State private var showingNewShower = false
    @State private var previewingPhoto: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        Divider()
                        sleepSection
                        Divider()
                        mealSection
                        Divider()
                        showerSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(
                    selectedDate: appViewModel.selectedDate,
                    allowedRange: appViewModel.availableDateRange
                ) { date in
                    Task { await appViewModel.selectDate(date) }
                }
            }
            .sheet(item: $editingSleepTarget) { target in
                SleepEditorSheet(
                    target: target,
                    currentValue: target == .bedtime ? appViewModel.dailyRecord.sleepRecord.bedtimePreviousNight : appViewModel.dailyRecord.sleepRecord.wakeTimeCurrentDay,
                    baseDate: appViewModel.selectedDate
                ) { value in
                    Task {
                        switch target {
                        case .bedtime:
                            await appViewModel.updateBedtime(value)
                        case .wakeTime:
                            await appViewModel.updateWakeTime(value)
                        }
                    }
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
                    canDelete: appViewModel.canDeleteMealEntry(context.entry),
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
                .presentationDetents([.fraction(0.42)])
                .presentationBackground(AppTheme.background)
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
                .presentationDetents([.fraction(0.42)])
                .presentationBackground(AppTheme.background)
            }
            .alert("提示", isPresented: .constant(appViewModel.errorMessage != nil), actions: {
                Button("知道了") {
                    appViewModel.errorMessage = nil
                }
            }, message: {
                Text(appViewModel.errorMessage ?? "")
            })
            .fullScreenCover(item: Binding(
                get: { previewingPhoto.map { IdentifiableImage(image: $0) } },
                set: { if $0 == nil { previewingPhoto = nil } }
            )) { item in
                PhotoPreviewOverlay(image: item.image) {
                    previewingPhoto = nil
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Calendar.current.isDateInToday(appViewModel.selectedDate) ? "今天是" : "这一天")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    Button {
                        showingDatePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(appViewModel.selectedDate.formattedDayTitle())
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
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
                        .background(AppTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                Label {
                    Text(formattedSun(appViewModel.dailyRecord.sunTimes?.sunrise))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "sunrise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.sunriseAccent)
                }

                Label {
                    Text(formattedSun(appViewModel.dailyRecord.sunTimes?.sunset))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "sunset")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.sleepAccent)
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Sleep

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

            Text(durationText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(durationText == "-- h -- m" ? AppTheme.secondaryText : AppTheme.primaryText)

            HStack(spacing: 24) {
                Button {
                    editingSleepTarget = .bedtime
                } label: {
                    HStack(spacing: 6) {
                        Text("入睡")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(appViewModel.dailyRecord.sleepRecord.bedtimePreviousNight?.displayClockTime ?? "--:--")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.sleepAccent)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)

                Button {
                    editingSleepTarget = .wakeTime
                } label: {
                    HStack(spacing: 6) {
                        Text("起床")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(appViewModel.dailyRecord.sleepRecord.wakeTimeCurrentDay?.displayClockTime ?? "--:--")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.wakeAccent)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if appViewModel.dailyRecord.sleepRecord.hasStageData {
                SleepStageBar(intervals: appViewModel.dailyRecord.sleepRecord.stageIntervals)
            }
        }
        .sectionStyle()
    }

    // MARK: - Meals

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "餐食", subtitle: nil)

            VStack(spacing: 0) {
                ForEach(Array(appViewModel.dailyRecord.meals.enumerated()), id: \.element.id) { index, meal in
                    if index > 0 {
                        Divider().padding(.leading, 4)
                    }
                    mealRow(meal)
                }

                Divider().padding(.leading, 4)

                Button {
                    editingMealContext = MealEditorContext(
                        entry: MealEntry(
                            mealKind: .custom,
                            customTitle: "加餐",
                            status: .logged,
                            time: appViewModel.selectedDate.settingTime(hour: 15, minute: 0),
                            photoURL: nil
                        ),
                        preferredSource: .timeOnly
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text("添加餐次")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(!appViewModel.canEditSelectedDate)
                .opacity(appViewModel.canEditSelectedDate ? 1 : 0.45)
            }
        }
        .sectionStyle()
    }

    private func mealRow(_ meal: MealEntry) -> some View {
        let effectiveStatus = meal.effectiveStatus(on: appViewModel.selectedDate)
        let accentColor = mealAccentColor(meal)

        return HStack(spacing: 12) {
            Menu {
                let isLogged = meal.time != nil || meal.hasPhoto
                let canDeleteMeal = appViewModel.canDeleteMealEntry(meal)

                if meal.hasPhoto {
                    Button("编辑照片") {
                        openMealEditor(meal, with: .editPhoto)
                    }
                    Button("修改时间") {
                        openMealEditor(meal, with: .editTime)
                    }
                    Button("删除照片", role: .destructive) {
                        Task { await appViewModel.removeMealPhoto(meal) }
                    }
                    if canDeleteMeal {
                        Button("删除餐次", role: .destructive) {
                            Task { await appViewModel.deleteMeal(meal) }
                        }
                    } else {
                        Button("删除记录", role: .destructive) {
                            Task { await appViewModel.clearMealRecord(meal) }
                        }
                    }
                } else if isLogged {
                    Button("添加图片") {
                        openMealEditor(meal, with: .addPhoto)
                    }
                    Button("修改时间") {
                        openMealEditor(meal, with: .editTime)
                    }
                    if canDeleteMeal {
                        Button("删除餐次", role: .destructive) {
                            Task { await appViewModel.deleteMeal(meal) }
                        }
                    } else {
                        Button("删除记录", role: .destructive) {
                            Task { await appViewModel.clearMealRecord(meal) }
                        }
                    }
                } else {
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
                    if canDeleteMeal {
                        Button("删除餐次", role: .destructive) {
                            Task { await appViewModel.deleteMeal(meal) }
                        }
                    }
                    Button("跳过", role: .destructive) {
                        Task { await appViewModel.skipMeal(meal) }
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    Text(meal.displayTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    switch effectiveStatus {
                    case .logged:
                        Text(meal.time?.displayClockTime ?? "已记录")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                    case .skipped:
                        Text("跳过")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.warning)
                    case .empty:
                        Text("未记录")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!appViewModel.canEditSelectedDate)

            if let thumbnail = mealThumbnail(meal) {
                Button {
                    previewingPhoto = thumbnail
                } label: {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Showers

    private var showerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "洗澡",
                subtitle: nil,
                actionTitle: appViewModel.canEditSelectedDate ? "添加" : nil
            ) {
                showingNewShower = true
            }

            if appViewModel.dailyRecord.showers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "drop.degreesign")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.showerAccent)
                    Text("无记录")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appViewModel.dailyRecord.showers.enumerated()), id: \.element.id) { index, shower in
                        if index > 0 {
                            Divider().padding(.leading, 4)
                        }
                        HStack {
                            Button {
                                editingShower = shower
                            } label: {
                                Text(shower.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.showerAccent)
                                    .monospacedDigit()
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task { await appViewModel.deleteShower(shower) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.warning)
                            }
                            .buttonStyle(.plain)
                            .disabled(!appViewModel.canEditSelectedDate)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Helpers

    private var durationText: String {
        guard let duration = appViewModel.dailyRecord.sleepRecord.duration else {
            return "-- h -- m"
        }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return "\(hours) h \(minutes) m"
    }

    private func formattedSun(_ date: Date?) -> String {
        date?.displayClockTime ?? "--:--"
    }

    private func mealAccentColor(_ meal: MealEntry) -> Color {
        switch meal.mealKind {
        case .breakfast: AppTheme.wakeAccent
        case .lunch: AppTheme.accent
        case .dinner: AppTheme.sleepAccent
        case .custom: AppTheme.sunriseAccent
        }
    }

    private func mealThumbnail(_ meal: MealEntry) -> UIImage? {
        guard let photoURL = meal.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL)
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

    var id: String {
        "\(entry.id.uuidString)-\(String(describing: preferredSource))"
    }
}

// MARK: - Sleep Stage Bar

struct SleepStageBar: View {
    let intervals: [SleepStageInterval]

    private var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    private var stageDurations: [(stage: SleepStage, duration: TimeInterval)] {
        let grouped = Dictionary(grouping: intervals, by: \.stage)
        return SleepStage.allCases.compactMap { stage in
            guard let intervals = grouped[stage] else { return nil }
            let total = intervals.reduce(0) { $0 + $1.duration }
            return (stage, total)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 1.5) {
                    ForEach(intervals) { interval in
                        let fraction = totalDuration > 0 ? interval.duration / totalDuration : 0
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(interval.stage.color)
                            .frame(width: max(2, geometry.size.width * fraction))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            HStack(spacing: 14) {
                ForEach(stageDurations, id: \.stage) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.stage.color)
                            .frame(width: 8, height: 8)
                        Text(item.stage.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(formatStageDuration(item.duration))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func formatStageDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Photo Preview

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct PhotoPreviewOverlay: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .padding(.top, 54)
            .padding(.leading, 18)
        }
    }
}
