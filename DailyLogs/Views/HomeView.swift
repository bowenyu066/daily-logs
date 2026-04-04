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
    @State private var pendingDestructiveAction: PendingDestructiveAction?

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
                    onSave: { updated, images in
                        Task { await appViewModel.saveMeal(updated, images: images) }
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
            .sheet(isPresented: $showingNewShower) {
                ShowerEditorSheet(
                    initialValue: ShowerEntry(
                        time: appViewModel.selectedDate.anchoringCurrentClockTime(
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
            .sheet(isPresented: $showingNewBowelMovement) {
                BowelMovementEditorSheet(
                    initialValue: BowelMovementEntry(
                        time: appViewModel.selectedDate.anchoringCurrentClockTime(
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
            .sheet(isPresented: $showingNewSexualActivity) {
                SexualActivityEditorSheet(
                    initialValue: SexualActivityEntry(
                        date: appViewModel.selectedDate,
                        time: appViewModel.selectedDate.anchoringCurrentClockTime(
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            .alert(item: $pendingDestructiveAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(action.message),
                    primaryButton: .destructive(Text(action.confirmTitle)) {
                        perform(action)
                    },
                    secondaryButton: .cancel(Text(NSLocalizedString("取消", comment: "")))
                )
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(appViewModel.dailyRecord.meals) { meal in
                        mealCard(meal)
                    }
                    addMealCard
                }
                .padding(.vertical, 4)
            }
        }
        .sectionStyle()
    }

    private func mealCard(_ meal: MealEntry) -> some View {
        let effectiveStatus = meal.effectiveStatus(on: appViewModel.selectedDate)
        let accentColor = mealAccentColor(meal)
        let canDeleteMeal = appViewModel.canDeleteMealEntry(meal)
        let photoCount = meal.photoURLs.count

        return VStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                Text(meal.displayTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                switch effectiveStatus {
                case .logged:
                    Text(meal.time.map {
                        appViewModel.displayedClockTime(
                            for: $0,
                            recordedTimeZoneIdentifier: meal.timeZoneIdentifier
                        )
                    } ?? NSLocalizedString("已记录", comment: ""))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                case .skipped:
                    Text(NSLocalizedString("跳过", comment: ""))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.warning)
                case .empty:
                    Text(NSLocalizedString("未记录", comment: ""))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            if photoCount == 0 {
                DashedMealPhotoPlaceholder()
                    .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170)
            } else {
                HStack(spacing: 10) {
                    ForEach(meal.photoURLs, id: \.self) { photoURL in
                        Button {
                            previewingPhotoURL = photoURL
                        } label: {
                            PhotoContentView(photoURL: photoURL, contentMode: .fill)
                                .frame(width: 104, height: 142)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if photoCount > 0 {
                Spacer(minLength: 0)
            }

            if photoCount == 0 {
                Button {
                    guard effectiveStatus != .skipped else { return }
                    Task { await appViewModel.skipMeal(meal) }
                } label: {
                    Text(NSLocalizedString("跳过", comment: ""))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(effectiveStatus == .skipped ? .white : AppTheme.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            effectiveStatus == .skipped ? AppTheme.warning : AppTheme.warning.opacity(0.12)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!appViewModel.canEditSelectedDate || effectiveStatus == .skipped)
            } else {
                Button {
                    openMealEditor(meal, with: .addPhoto)
                } label: {
                    Text(NSLocalizedString("添加照片", comment: ""))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!appViewModel.canEditSelectedDate)
            }
        }
        .frame(width: mealCardWidth(photoCount: photoCount), height: mealCardHeight, alignment: .top)
        .padding(18)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.8), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            guard appViewModel.canEditSelectedDate else { return }
            openMealEditor(meal, with: .editRecord)
        }
        .contextMenu {
            if effectiveStatus == .logged {
                Button(NSLocalizedString("修改记录", comment: "")) {
                    openMealEditor(meal, with: .editRecord)
                }
                if canDeleteMeal {
                    Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                        pendingDestructiveAction = .deleteMeal(meal)
                    }
                } else {
                    Button(NSLocalizedString("删除记录", comment: ""), role: .destructive) {
                        pendingDestructiveAction = .clearMealRecord(meal)
                    }
                }
            } else {
                Button(NSLocalizedString("添加记录", comment: "")) {
                    openMealEditor(meal, with: .editRecord)
                }
                if canDeleteMeal {
                    Button(NSLocalizedString("删除餐次", comment: ""), role: .destructive) {
                        pendingDestructiveAction = .deleteMeal(meal)
                    }
                }
                Button(NSLocalizedString("跳过", comment: ""), role: .destructive) {
                    Task { await appViewModel.skipMeal(meal) }
                }
            }
        }
        .opacity(appViewModel.canEditSelectedDate ? 1 : 0.65)
    }

    private var addMealCard: some View {
        Button {
            editingMealContext = MealEditorContext(
                entry: MealEntry(
                    mealKind: .custom,
                    customTitle: NSLocalizedString("加餐", comment: ""),
                    status: .empty
                ),
                preferredSource: .editRecord
            )
        } label: {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(NSLocalizedString("添加餐次", comment: ""))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(width: 178, height: mealCardHeight + 36)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [8, 8]))
                    .foregroundStyle(AppTheme.accent.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .disabled(!appViewModel.canEditSelectedDate)
        .opacity(appViewModel.canEditSelectedDate ? 1 : 0.45)
    }

    private func mealCardWidth(photoCount: Int) -> CGFloat {
        let minimumWidth: CGFloat = 188
        guard photoCount > 0 else { return minimumWidth }
        let thumbnailWidth: CGFloat = 104
        let spacing: CGFloat = 10
        let horizontalPadding: CGFloat = 36
        let photoRowWidth = (CGFloat(photoCount) * thumbnailWidth) + (CGFloat(max(photoCount - 1, 0)) * spacing)
        return max(minimumWidth, photoRowWidth + horizontalPadding)
    }

    private var mealCardHeight: CGFloat {
        286
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    editingShower = shower
                                } label: {
                                    Text(shower.time.map {
                                        appViewModel.displayedShortTime(
                                            for: $0,
                                            recordedTimeZoneIdentifier: shower.timeZoneIdentifier
                                        )
                                    } ?? NSLocalizedString("已记录", comment: ""))
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.showerAccent)
                                        .monospacedDigit()
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    pendingDestructiveAction = .deleteShower(shower)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .disabled(!appViewModel.canEditSelectedDate)
                            }

                            if let note = shower.note, !note.isEmpty {
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
                                    Text(entry.time.map {
                                        appViewModel.displayedShortTime(
                                            for: $0,
                                            recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                                        )
                                    } ?? NSLocalizedString("已记录", comment: ""))
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(.brown)
                                        .monospacedDigit()
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    pendingDestructiveAction = .deleteBowelMovement(entry)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.red)
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
                                    pendingDestructiveAction = .deleteSexualActivity(entry)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.red)
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

    private func perform(_ action: PendingDestructiveAction) {
        switch action {
        case .removeMealPhoto(let meal):
            Task { await appViewModel.removeMealPhoto(meal) }
        case .deleteMeal(let meal):
            Task { await appViewModel.deleteMeal(meal) }
        case .clearMealRecord(let meal):
            Task { await appViewModel.clearMealRecord(meal) }
        case .deleteShower(let shower):
            Task { await appViewModel.deleteShower(shower) }
        case .deleteBowelMovement(let entry):
            Task { await appViewModel.deleteBowelMovement(entry) }
        case .deleteSexualActivity(let entry):
            Task { await appViewModel.deleteSexualActivity(entry) }
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

private enum PendingDestructiveAction: Identifiable {
    case removeMealPhoto(MealEntry)
    case deleteMeal(MealEntry)
    case clearMealRecord(MealEntry)
    case deleteShower(ShowerEntry)
    case deleteBowelMovement(BowelMovementEntry)
    case deleteSexualActivity(SexualActivityEntry)

    var id: String {
        switch self {
        case .removeMealPhoto(let meal):
            return "remove-photo-\(meal.id)"
        case .deleteMeal(let meal):
            return "delete-meal-\(meal.id)"
        case .clearMealRecord(let meal):
            return "clear-meal-\(meal.id)"
        case .deleteShower(let shower):
            return "delete-shower-\(shower.id)"
        case .deleteBowelMovement(let entry):
            return "delete-bowel-\(entry.id)"
        case .deleteSexualActivity(let entry):
            return "delete-sex-\(entry.id)"
        }
    }

    var title: String {
        switch self {
        case .removeMealPhoto:
            return NSLocalizedString("删除照片？", comment: "")
        case .deleteMeal:
            return NSLocalizedString("删除餐次？", comment: "")
        case .clearMealRecord:
            return NSLocalizedString("删除记录？", comment: "")
        case .deleteShower, .deleteBowelMovement, .deleteSexualActivity:
            return NSLocalizedString("删除记录？", comment: "")
        }
    }

    var message: String {
        switch self {
        case .removeMealPhoto:
            return NSLocalizedString("此操作会移除这张照片，且无法撤销。", comment: "")
        case .deleteMeal:
            return NSLocalizedString("此操作会删除整个餐次，且无法撤销。", comment: "")
        case .clearMealRecord, .deleteShower, .deleteBowelMovement, .deleteSexualActivity:
            return NSLocalizedString("此操作无法撤销。", comment: "")
        }
    }

    var confirmTitle: String {
        switch self {
        case .removeMealPhoto:
            return NSLocalizedString("删除照片", comment: "")
        case .deleteMeal:
            return NSLocalizedString("删除餐次", comment: "")
        case .clearMealRecord, .deleteShower, .deleteBowelMovement, .deleteSexualActivity:
            return NSLocalizedString("删除记录", comment: "")
        }
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

struct DashedMealPhotoPlaceholder: View {
    var title: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [8, 8]))
                .foregroundStyle(AppTheme.border.opacity(0.9))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
