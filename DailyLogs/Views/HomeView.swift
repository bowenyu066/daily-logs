import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingDatePicker = false
    @State private var editingSleepTarget: SleepEditorTarget?
    @State private var showingTargetBedtime = false
    @State private var editingMealContext: MealEditorContext?
    @State private var editingShower: ShowerEntry?
    @State private var showingNewShower = false
    @State private var editingBowelMovement: BowelMovementEntry?
    @State private var showingNewBowelMovement = false
    @State private var editingSexualActivity: SexualActivityEntry?
    @State private var showingNewSexualActivity = false
    @State private var previewingPhotoURL: String?
    @State private var showingHealthKitSyncConfirmation = false
    @State private var showingSleepNoteEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        if sectionVisible(.sleep) {
                            Divider()
                            sleepSection
                        }
                        if sectionVisible(.meals) {
                            Divider()
                            mealSection
                        }
                        if sectionVisible(.showers) {
                            Divider()
                            showerSection
                        }
                        if sectionVisible(.bowelMovements) {
                            Divider()
                            bowelMovementSection
                        }
                        if sectionVisible(.sexualActivity) {
                            Divider()
                            sexualActivitySection
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .refreshable {
                    await appViewModel.refreshHomeData()
                }
            }
            .navigationTitle(NSLocalizedString("主页", comment: ""))
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
            .sheet(isPresented: $showingSleepNoteEditor) {
                SleepNoteEditorSheet(note: appViewModel.dailyRecord.sleepRecord.note) { note in
                    Task { await appViewModel.updateSleepNote(note) }
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
                    initialValue: ShowerEntry(
                        time: appViewModel.selectedDate.settingTime(
                            hour: 21,
                            minute: 30,
                            in: appViewModel.displayedTimeZone(for: nil)
                        )
                    ),
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
            .sheet(item: $editingBowelMovement) { entry in
                BowelMovementEditorSheet(
                    initialValue: entry,
                    baseDate: appViewModel.selectedDate,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated in
                        Task { await appViewModel.saveBowelMovement(updated) }
                    },
                    onDelete: {
                        Task { await appViewModel.deleteBowelMovement(entry) }
                    }
                )
                .presentationDetents([.fraction(0.42)])
                .presentationBackground(AppTheme.background)
            }
            .sheet(isPresented: $showingNewBowelMovement) {
                BowelMovementEditorSheet(
                    initialValue: BowelMovementEntry(
                        time: appViewModel.selectedDate.settingTime(
                            hour: 8,
                            minute: 0,
                            in: appViewModel.displayedTimeZone(for: nil)
                        )
                    ),
                    baseDate: appViewModel.selectedDate,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated in
                        Task { await appViewModel.saveBowelMovement(updated) }
                    },
                    onDelete: nil
                )
                .presentationDetents([.fraction(0.42)])
                .presentationBackground(AppTheme.background)
            }
            .sheet(item: $editingSexualActivity) { entry in
                SexualActivityEditorSheet(
                    initialValue: entry,
                    baseDate: appViewModel.selectedDate,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated in
                        Task { await appViewModel.saveSexualActivity(updated) }
                    },
                    onDelete: {
                        Task { await appViewModel.deleteSexualActivity(entry) }
                    }
                )
                .presentationDetents([.fraction(0.52)])
                .presentationBackground(AppTheme.background)
            }
            .sheet(isPresented: $showingNewSexualActivity) {
                SexualActivityEditorSheet(
                    initialValue: SexualActivityEntry(
                        date: appViewModel.selectedDate,
                        time: appViewModel.selectedDate.settingTime(
                            hour: 22,
                            minute: 0,
                            in: appViewModel.displayedTimeZone(for: nil)
                        )
                    ),
                    baseDate: appViewModel.selectedDate,
                    isEditable: appViewModel.canEditSelectedDate,
                    onSave: { updated in
                        Task { await appViewModel.saveSexualActivity(updated) }
                    },
                    onDelete: nil
                )
                .presentationDetents([.fraction(0.52)])
                .presentationBackground(AppTheme.background)
            }
            .alert(NSLocalizedString("提示", comment: ""), isPresented: .constant(appViewModel.errorMessage != nil), actions: {
                Button(NSLocalizedString("知道了", comment: "")) {
                    appViewModel.errorMessage = nil
                }
            }, message: {
                Text(appViewModel.errorMessage ?? "")
            })
            .alert(NSLocalizedString("是否从 Apple Health 同步数据？", comment: ""), isPresented: $showingHealthKitSyncConfirmation) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("确认", comment: "")) {
                    Task { await appViewModel.overwriteSleepWithHealthKit() }
                }
            } message: {
                Text(NSLocalizedString("此操作将会覆盖已有数据。", comment: ""))
            }
            .fullScreenCover(item: Binding(
                get: { previewingPhotoURL.map { IdentifiablePhoto(url: $0) } },
                set: { if $0 == nil { previewingPhotoURL = nil } }
            )) { item in
                PhotoPreviewOverlay(photoURL: item.url) {
                    previewingPhotoURL = nil
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Calendar.current.isDateInToday(appViewModel.selectedDate) ? LocalizedStringKey("今天是") : LocalizedStringKey("这一天"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    Button {
                        showingDatePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(appViewModel.selectedDate.formattedDayTitle(locale: locale))
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

            if sectionVisible(.sunTimes) {
                HStack(spacing: 16) {
                    Label {
                        Text(formattedSun(
                            appViewModel.dailyRecord.sunTimes?.sunrise,
                            timeZoneIdentifier: appViewModel.dailyRecord.sunTimes?.timeZoneIdentifier
                        ))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "sunrise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.sunriseAccent)
                    }

                    Label {
                        Text(formattedSun(
                            appViewModel.dailyRecord.sunTimes?.sunset,
                            timeZoneIdentifier: appViewModel.dailyRecord.sunTimes?.timeZoneIdentifier
                        ))
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
        }
        .sectionStyle()
    }

    // MARK: - Sleep

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("睡眠", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                if appViewModel.preferences.healthKitSyncEnabled {
                    Button {
                        showingHealthKitSyncConfirmation = true
                    } label: {
                        Label(NSLocalizedString("同步", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.accentSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showingSleepNoteEditor = true
                } label: {
                    Label(NSLocalizedString("备注", comment: ""), systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.elevatedSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!appViewModel.canEditSelectedDate)
                .opacity(appViewModel.canEditSelectedDate ? 1 : 0.45)
                Button {
                    showingTargetBedtime = true
                } label: {
                    Text(NSLocalizedString("目标入睡：", comment: "") + appViewModel.formattedTargetBedtime())
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
                        Text(NSLocalizedString("入睡", comment: ""))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(appViewModel.displayedClockTime(
                            for: appViewModel.dailyRecord.sleepRecord.bedtimePreviousNight,
                            recordedTimeZoneIdentifier: appViewModel.dailyRecord.sleepRecord.timeZoneIdentifier
                        ))
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
                        Text(NSLocalizedString("起床", comment: ""))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(appViewModel.displayedClockTime(
                            for: appViewModel.dailyRecord.sleepRecord.wakeTimeCurrentDay,
                            recordedTimeZoneIdentifier: appViewModel.dailyRecord.sleepRecord.timeZoneIdentifier
                        ))
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

            if let note = appViewModel.dailyRecord.sleepRecord.note, !note.isEmpty {
                notePreview(note)
            }
        }
        .sectionStyle()
    }

    // MARK: - Meals

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("餐食", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }

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
                            customTitle: NSLocalizedString("加餐", comment: ""),
                            status: .logged,
                            time: appViewModel.selectedDate.settingTime(
                                hour: 15,
                                minute: 0,
                                in: appViewModel.displayedTimeZone(for: nil)
                            ),
                            photoURL: nil
                        ),
                        preferredSource: .timeOnly
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text(NSLocalizedString("添加餐次", comment: ""))
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

                if isLogged {
                    Button(NSLocalizedString("修改记录", comment: "")) {
                        openMealEditor(meal, with: .editRecord)
                    }
                    if meal.hasPhoto {
                        Button(NSLocalizedString("删除照片", comment: ""), role: .destructive) {
                            Task { await appViewModel.removeMealPhoto(meal) }
                        }
                    }
                    if canDeleteMeal {
                        Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                            Task { await appViewModel.deleteMeal(meal) }
                        }
                    } else {
                        Button(NSLocalizedString("删除记录", comment: ""), role: .destructive) {
                            Task { await appViewModel.clearMealRecord(meal) }
                        }
                    }
                } else {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(NSLocalizedString("拍照", comment: "")) {
                            openMealEditor(meal, with: .camera)
                        }
                    }
                    Button(NSLocalizedString("选择相册照片", comment: "")) {
                        openMealEditor(meal, with: .photoLibrary)
                    }
                    Button(NSLocalizedString("仅记录时间", comment: "")) {
                        openMealEditor(meal, with: .timeOnly)
                    }
                    if canDeleteMeal {
                        Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                            Task { await appViewModel.deleteMeal(meal) }
                        }
                    }
                    Button(NSLocalizedString("跳过", comment: ""), role: .destructive) {
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
                        Text(meal.time.map {
                            appViewModel.displayedClockTime(
                                for: $0,
                                recordedTimeZoneIdentifier: meal.timeZoneIdentifier
                            )
                        } ?? NSLocalizedString("已记录", comment: ""))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                    case .skipped:
                        Text(NSLocalizedString("跳过", comment: ""))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.warning)
                    case .empty:
                        Text(NSLocalizedString("未记录", comment: ""))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!appViewModel.canEditSelectedDate)

            if let photoURL = meal.photoURL {
                Button {
                    previewingPhotoURL = photoURL
                } label: {
                    PhotoContentView(photoURL: photoURL, contentMode: .fill)
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
            HStack(alignment: .center) {
                Text(NSLocalizedString("洗澡", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                if appViewModel.canEditSelectedDate {
                    Button(NSLocalizedString("添加", comment: "")) {
                        showingNewShower = true
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
                }
                Spacer()
            }

            if appViewModel.dailyRecord.showers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "drop.degreesign")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.showerAccent)
                    Text(NSLocalizedString("无记录", comment: ""))
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
                                Text(appViewModel.displayedShortTime(
                                    for: shower.time,
                                    recordedTimeZoneIdentifier: shower.timeZoneIdentifier
                                ))
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

    // MARK: - Bowel Movements

    private var bowelMovementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(NSLocalizedString("排便", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                if appViewModel.canEditSelectedDate {
                    Button(NSLocalizedString("添加", comment: "")) {
                        showingNewBowelMovement = true
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
                }
                Spacer()
            }

            if appViewModel.dailyRecord.bowelMovements.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "leaf")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.brown)
                    Text(NSLocalizedString("无记录", comment: ""))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appViewModel.dailyRecord.bowelMovements.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, 4)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    editingBowelMovement = entry
                                } label: {
                                    Text(appViewModel.displayedShortTime(
                                        for: entry.time,
                                        recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                                    ))
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(.brown)
                                        .monospacedDigit()
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    Task { await appViewModel.deleteBowelMovement(entry) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.warning)
                                }
                                .buttonStyle(.plain)
                                .disabled(!appViewModel.canEditSelectedDate)
                            }

                            if let note = entry.note, !note.isEmpty {
                                notePreview(note)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Sexual Activity

    private var sexualActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(NSLocalizedString("性生活", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                if appViewModel.canEditSelectedDate {
                    Button(NSLocalizedString("添加", comment: "")) {
                        showingNewSexualActivity = true
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
                }
                Spacer()
            }

            if appViewModel.dailyRecord.sexualActivities.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.pink)
                    Text(NSLocalizedString("无记录", comment: ""))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appViewModel.dailyRecord.sexualActivities.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, 4)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    editingSexualActivity = entry
                                } label: {
                                    HStack(spacing: 8) {
                                        if let time = entry.time {
                                            Text(appViewModel.displayedShortTime(
                                                for: time,
                                                recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                                            ))
                                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                                .foregroundStyle(.pink)
                                                .monospacedDigit()
                                        } else {
                                            Text(NSLocalizedString("已记录", comment: ""))
                                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                                .foregroundStyle(.pink)
                                        }
                                        if entry.isMasturbation {
                                            Text(NSLocalizedString("自慰", comment: ""))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.pink.opacity(0.7))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(.pink.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    Task { await appViewModel.deleteSexualActivity(entry) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.warning)
                                }
                                .buttonStyle(.plain)
                                .disabled(!appViewModel.canEditSelectedDate)
                            }

                            if let note = entry.note, !note.isEmpty {
                                notePreview(note)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Helpers

    private func sectionVisible(_ section: HomeSectionKind) -> Bool {
        appViewModel.preferences.visibleHomeSections.contains(section)
    }

    private var durationText: String {
        guard let duration = appViewModel.dailyRecord.sleepRecord.duration else {
            return "-- h -- m"
        }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        return "\(hours) h \(minutes) m"
    }

    private func formattedSun(_ date: Date?, timeZoneIdentifier: String?) -> String {
        appViewModel.displayedClockTime(for: date, recordedTimeZoneIdentifier: timeZoneIdentifier)
    }

    private func mealAccentColor(_ meal: MealEntry) -> Color {
        switch meal.mealKind {
        case .breakfast: AppTheme.wakeAccent
        case .lunch: AppTheme.accent
        case .dinner: AppTheme.sleepAccent
        case .custom: AppTheme.sunriseAccent
        }
    }

    private func notePreview(_ note: String) -> some View {
        Text(note)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 86), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(stageDurations, id: \.stage) { item in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(item.stage.color)
                            .frame(width: 7, height: 7)
                        Text("\(item.stage.title) \(formatStageDuration(item.duration))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
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

private struct IdentifiablePhoto: Identifiable {
    let id = UUID()
    let url: String
}

struct PhotoPreviewOverlay: View {
    let photoURL: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PhotoContentView(photoURL: photoURL, contentMode: .fit)
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
