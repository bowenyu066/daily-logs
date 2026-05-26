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
    @State private var previewingVideoURL: String?
    @State private var showingHealthKitSyncConfirmation = false
    @State private var showingSleepNoteEditor = false
    @State private var pendingDestructiveAction: PendingDestructiveAction?
    @State private var showingDailyVideoSourceOptions = false
    @State private var videoPickerSource: UIImagePickerController.SourceType?
    @State private var trimmingVideoSource: IdentifiableVideoSource?
    @State private var travelEditorContext: TravelEditorContext?
    @State private var travelSleepEditorContext: TravelSleepEditorContext?
#if DEBUG
    @State private var showingTravelDebugPanel = false
#endif

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        let selectedTravelPlans = appViewModel.travelPlans(on: appViewModel.selectedDate)
                        if !selectedTravelPlans.isEmpty {
                            Divider()
                            travelSection(selectedTravelPlans)
                        }
                        if sectionVisible(.sleep) {
                            Divider()
                            sleepSection
                        }
                        if sectionVisible(.meals) {
                            Divider()
                            mealSection
                        }
                        if sectionVisible(.dailyVideo) {
                            Divider()
                            dailyVideoSection
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
            .fullScreenCover(isPresented: $showingDatePicker) {
                DatePickerSheet(
                    selectedDate: appViewModel.selectedDate,
                    allowedRange: appViewModel.availableDateRange,
                    overlayRange: appViewModel.travelOverlayDateRange,
                    travelPlansForDate: { appViewModel.travelPlans(on: $0) },
                    onTravelPlanSelected: { plan in
                        travelEditorContext = .edit(plan)
                    }
                ) { date in
                    Task { await appViewModel.selectDate(date) }
                }
            }
            .sheet(item: $travelEditorContext) { context in
                TravelPlanEditorSheet(
                    plan: context.plan,
                    onSave: { plan in
                        Task { await appViewModel.saveTravelPlan(plan) }
                    },
                    onDelete: context.plan.map { plan in
                        { Task { await appViewModel.deleteTravelPlan(plan) } }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
            .sheet(item: $travelSleepEditorContext) { context in
                TravelSleepSessionEditorSheet(
                    plan: context.plan,
                    session: context.session,
                    onSave: { session, plan in
                        Task { await appViewModel.saveTravelSleepSession(session, in: plan) }
                    },
                    onDelete: context.session.map { session in
                        { Task { await appViewModel.deleteTravelSleepSession(session, in: context.plan) } }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
#if DEBUG
            .sheet(isPresented: $showingTravelDebugPanel) {
                TravelPlanDebugPanelSheet(
                    plans: appViewModel.travelPlans,
                    preferences: appViewModel.preferences,
                    selectedDate: appViewModel.selectedDate,
                    onStartHypotheticalTravel: {
                        Task {
                            await appViewModel.startDebugHypotheticalTravel()
                            showingTravelDebugPanel = false
                        }
                    },
                    onClearHypotheticalTravel: {
                        Task {
                            await appViewModel.clearDebugHypotheticalTravel()
                            showingTravelDebugPanel = false
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.background)
            }
#endif
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
                    fallbackTime: appViewModel.suggestedEventTimestamp(
                        for: appViewModel.selectedDate,
                        recordedTimeZoneIdentifier: shower.timeZoneIdentifier
                    ),
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
                        time: appViewModel.suggestedEventTimestamp(
                            for: appViewModel.selectedDate,
                            recordedTimeZoneIdentifier: nil
                        )
                    ),
                    baseDate: appViewModel.selectedDate,
                    fallbackTime: appViewModel.suggestedEventTimestamp(
                        for: appViewModel.selectedDate,
                        recordedTimeZoneIdentifier: nil
                    ),
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
                    fallbackTime: appViewModel.suggestedEventTimestamp(
                        for: appViewModel.selectedDate,
                        recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                    ),
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
                        time: appViewModel.suggestedEventTimestamp(
                            for: appViewModel.selectedDate,
                            recordedTimeZoneIdentifier: nil
                        )
                    ),
                    baseDate: appViewModel.selectedDate,
                    fallbackTime: appViewModel.suggestedEventTimestamp(
                        for: appViewModel.selectedDate,
                        recordedTimeZoneIdentifier: nil
                    ),
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
                    fallbackTime: appViewModel.suggestedEventTimestamp(
                        for: appViewModel.selectedDate,
                        recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                    ),
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
                        time: appViewModel.suggestedEventTimestamp(
                            for: appViewModel.selectedDate,
                            recordedTimeZoneIdentifier: nil
                        )
                    ),
                    baseDate: appViewModel.selectedDate,
                    fallbackTime: appViewModel.suggestedEventTimestamp(
                        for: appViewModel.selectedDate,
                        recordedTimeZoneIdentifier: nil
                    ),
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
            .sheet(isPresented: Binding(
                get: { videoPickerSource != nil },
                set: { if !$0 { videoPickerSource = nil } }
            )) {
                if let videoPickerSource {
                    DailyVideoPicker(sourceType: videoPickerSource) { url in
                        self.videoPickerSource = nil
                        guard let url else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            trimmingVideoSource = IdentifiableVideoSource(url: url)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .fullScreenCover(item: $trimmingVideoSource) { source in
                DailyVideoTrimmerSheet(sourceURL: source.url) { exportedURL, duration in
                    Task {
                        await appViewModel.saveDailyVideo(from: exportedURL, duration: duration)
                        try? FileManager.default.removeItem(at: exportedURL)
                        try? FileManager.default.removeItem(at: source.url)
                    }
                }
            }
            .fullScreenCover(item: Binding(
                get: { previewingPhotoURL.map { IdentifiablePhoto(url: $0) } },
                set: { if $0 == nil { previewingPhotoURL = nil } }
            )) { item in
                PhotoPreviewOverlay(photoURL: item.url) {
                    previewingPhotoURL = nil
                }
            }
            .fullScreenCover(item: Binding(
                get: { previewingVideoURL.map { IdentifiableVideo(url: $0) } },
                set: { if $0 == nil { previewingVideoURL = nil } }
            )) { item in
                DailyVideoPlaybackOverlay(videoURL: item.url) {
                    previewingVideoURL = nil
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        let activeTravelPlan = appViewModel.activeTravelPlan(on: appViewModel.selectedDate)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let activeTravelPlan {
                        Text(NSLocalizedString("现在你在旅途中", comment: ""))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Button {
                            showingDatePicker = true
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(activeTravelHeaderTitle(activeTravelPlan))
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Text(activeTravelHeaderSubtitle(activeTravelPlan))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.accent)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
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
                }

                Spacer()

                Button {
                    travelEditorContext = .new
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.accentSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

#if DEBUG
                Button {
                    showingTravelDebugPanel = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.warning.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
#endif

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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Label {
                            Text(appViewModel.currentLocationName ?? "--")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }

                        Spacer(minLength: 8)

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

                    Label {
                        Text(appViewModel.currentWeatherSummary())
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    } icon: {
                        Image(systemName: appViewModel.currentWeather?.symbolName ?? "cloud.sun.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.sunriseAccent)
                    }
                }
            }
        }
        .sectionStyle()
    }

    // MARK: - Travel

    private func travelSection(_ plans: [TravelPlan]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("旅行", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }

            ForEach(plans) { plan in
                travelPlanCard(plan)
            }
        }
        .sectionStyle()
    }

    private func travelPlanCard(_ plan: TravelPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayTitle)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(travelStageSummary(for: plan))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(plan.status.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(travelClockText(for: plan, now: context.date))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                    travelSegmentRow(segment, index: index, isCurrent: segment.id == plan.currentSegmentID)
                }
            }

            HStack(spacing: 10) {
                if plan.status != .planned {
                    Button {
                        Task { await appViewModel.retreatTravelPlan(plan) }
                    } label: {
                        Label(NSLocalizedString("上一阶段", comment: ""), systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(AppTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await appViewModel.advanceTravelPlan(plan) }
                } label: {
                    Text(nextTravelActionTitle(for: plan))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.actionFill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(plan.status == .completed)
                .opacity(plan.status == .completed ? 0.45 : 1)

                if plan.status.allowsPlanEditing {
                    Button {
                        travelEditorContext = .edit(plan)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.8), lineWidth: 1)
        }
    }

    private func travelSegmentRow(_ segment: TravelSegment, index: Int, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Color.white : AppTheme.secondaryText)
                .frame(width: 22, height: 22)
                .background(isCurrent ? AppTheme.accent : AppTheme.mutedFill)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(segment.flightDisplayTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text(travelSegmentTimeSummary(segment))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(travelDurationText(segment.actualDuration ?? segment.plannedDuration))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .monospacedDigit()
        }
        .padding(12)
        .background(isCurrent ? AppTheme.accentSoft : AppTheme.mutedFill.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func travelSleepSection(_ plan: TravelPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(NSLocalizedString("旅行睡眠", comment: ""), systemImage: "bed.double.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                if appViewModel.canEditSelectedDate, plan.status != .planned {
                    Button {
                        travelSleepEditorContext = .new(plan)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.sleepAccent)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.sleepAccent.opacity(0.13))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if plan.sleepSessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.sleepAccent)
                    Text(plan.status == .planned ? NSLocalizedString("进入旅行模式后可添加多段睡眠", comment: "") : NSLocalizedString("暂无睡眠记录", comment: ""))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(plan.sleepSessions) { session in
                        Button {
                            travelSleepEditorContext = .edit(plan, session)
                        } label: {
                            travelSleepRow(session, in: plan)
                        }
                        .buttonStyle(.plain)
                        .disabled(!appViewModel.canEditSelectedDate)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.elevatedSurface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func travelSleepRow(_ session: TravelSleepSession, in plan: TravelPlan) -> some View {
        let context = TravelRecordContext(
            planID: plan.id,
            segmentID: session.segmentID,
            phase: session.phase
        )

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.sleepAccent)
                .frame(width: 28, height: 28)
                .background(AppTheme.sleepAccent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                travelAwareTime(
                    session.startTime,
                    context: context,
                    fallback: appViewModel.displayedShortTime(
                        for: session.startTime,
                        recordedTimeZoneIdentifier: session.timeZoneIdentifier
                    ),
                    accent: AppTheme.sleepAccent,
                    isCompact: false
                )

                Text(NSLocalizedString("醒来：", comment: "") + (appViewModel.travelTimeText(for: session.endTime, context: context) ?? appViewModel.displayedShortTime(for: session.endTime, recordedTimeZoneIdentifier: session.timeZoneIdentifier)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Text(travelDurationText(session.duration))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.sleepAccent)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func travelTimelineSection(_ plan: TravelPlan) -> some View {
        let groupedItems = plan.segments.map { segment in
            (segment: segment, items: travelTimelineItems(for: plan, segmentID: segment.id))
        }
        let unassignedItems = travelTimelineItems(for: plan, segmentID: nil)
        let hasItems = groupedItems.contains { !$0.items.isEmpty } || !unassignedItems.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("旅行记录", comment: ""), systemImage: "list.bullet.clipboard")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            if hasItems {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedItems, id: \.segment.id) { group in
                        if !group.items.isEmpty {
                            travelTimelineGroup(title: group.segment.flightDisplayTitle, items: group.items)
                        }
                    }

                    if !unassignedItems.isEmpty {
                        travelTimelineGroup(title: NSLocalizedString("旅程其他阶段", comment: ""), items: unassignedItems)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(NSLocalizedString("旅行中的餐食、洗澡、排便等记录会按航段显示在这里", comment: ""))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(AppTheme.elevatedSurface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func travelTimelineGroup(title: String, items: [TravelTimelineItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)

            ForEach(items) { item in
                travelTimelineRow(item)
            }
        }
    }

    private func travelTimelineRow(_ item: TravelTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(item.accent)
                .frame(width: 26, height: 26)
                .background(item.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)

                travelAwareTime(
                    item.date,
                    context: item.context,
                    fallback: item.fallback,
                    accent: item.accent,
                    isCompact: false
                )

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func travelTimelineItems(for plan: TravelPlan, segmentID: UUID?) -> [TravelTimelineItem] {
        let meals = appViewModel.dailyRecord.meals.compactMap { meal -> TravelTimelineItem? in
            guard meal.travelContext?.planID == plan.id,
                  meal.travelContext?.segmentID == segmentID,
                  meal.status != .empty || meal.hasPhoto else {
                return nil
            }
            let fallback = meal.status == .skipped
                ? NSLocalizedString("跳过", comment: "")
                : meal.time.map { appViewModel.displayedShortTime(for: $0, recordedTimeZoneIdentifier: meal.timeZoneIdentifier) }
                    ?? NSLocalizedString("已记录", comment: "")
            return TravelTimelineItem(
                id: "meal-\(meal.id.uuidString)",
                title: meal.displayTitle,
                date: meal.time,
                context: meal.travelContext,
                fallback: fallback,
                accent: mealAccentColor(meal),
                systemImage: "fork.knife",
                note: meal.note
            )
        }

        let showers = appViewModel.dailyRecord.showers.compactMap { shower -> TravelTimelineItem? in
            guard shower.travelContext?.planID == plan.id,
                  shower.travelContext?.segmentID == segmentID else {
                return nil
            }
            return TravelTimelineItem(
                id: "shower-\(shower.id.uuidString)",
                title: NSLocalizedString("洗澡", comment: ""),
                date: shower.time,
                context: shower.travelContext,
                fallback: shower.time.map { appViewModel.displayedShortTime(for: $0, recordedTimeZoneIdentifier: shower.timeZoneIdentifier) }
                    ?? NSLocalizedString("已记录", comment: ""),
                accent: AppTheme.showerAccent,
                systemImage: "drop.degreesign",
                note: shower.note
            )
        }

        let bowelMovements = appViewModel.dailyRecord.bowelMovements.compactMap { entry -> TravelTimelineItem? in
            guard entry.travelContext?.planID == plan.id,
                  entry.travelContext?.segmentID == segmentID else {
                return nil
            }
            return TravelTimelineItem(
                id: "bowel-\(entry.id.uuidString)",
                title: NSLocalizedString("排便", comment: ""),
                date: entry.time,
                context: entry.travelContext,
                fallback: entry.time.map { appViewModel.displayedShortTime(for: $0, recordedTimeZoneIdentifier: entry.timeZoneIdentifier) }
                    ?? NSLocalizedString("已记录", comment: ""),
                accent: AppTheme.bowelAccent,
                systemImage: "leaf",
                note: entry.note
            )
        }

        let sexualActivities = appViewModel.dailyRecord.sexualActivities.compactMap { entry -> TravelTimelineItem? in
            guard entry.travelContext?.planID == plan.id,
                  entry.travelContext?.segmentID == segmentID else {
                return nil
            }
            return TravelTimelineItem(
                id: "sex-\(entry.id.uuidString)",
                title: entry.isMasturbation ? NSLocalizedString("自慰", comment: "") : NSLocalizedString("性生活", comment: ""),
                date: entry.time,
                context: entry.travelContext,
                fallback: entry.time.map { appViewModel.displayedShortTime(for: $0, recordedTimeZoneIdentifier: entry.timeZoneIdentifier) }
                    ?? NSLocalizedString("已记录", comment: ""),
                accent: AppTheme.sexualAccent,
                systemImage: "heart",
                note: entry.note
            )
        }

        return (meals + showers + bowelMovements + sexualActivities).sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case (let lhsDate?, let rhsDate?):
                return lhsDate < rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.title < rhs.title
            }
        }
    }

    // MARK: - Sleep

    @ViewBuilder
    private var sleepSection: some View {
        if let activePlan = appViewModel.activeTravelPlan(on: appViewModel.selectedDate) {
            travelSleepSection(activePlan)
                .sectionStyle()
        } else {
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
    }

    // MARK: - Meals

    private var mealSection: some View {
        let visibleMeals = appViewModel.travelPlans(on: appViewModel.selectedDate).isEmpty
            ? appViewModel.dailyRecord.meals
            : appViewModel.dailyRecord.meals.filter {
                $0.mealKind == .custom || $0.status == .logged || $0.status == .skipped || $0.hasPhoto
            }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("餐食", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(visibleMeals) { meal in
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
                    travelAwareTime(
                        meal.time,
                        context: meal.travelContext,
                        fallback: meal.time.map {
                            appViewModel.displayedClockTime(
                                for: $0,
                                recordedTimeZoneIdentifier: meal.timeZoneIdentifier
                            )
                        } ?? NSLocalizedString("已记录", comment: ""),
                        accent: accentColor
                    )
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
                    customTitle: defaultNewMealTitle,
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

    private var defaultNewMealTitle: String {
        if let activePlan = appViewModel.activeTravelPlan(on: appViewModel.selectedDate) {
            switch activePlan.status {
            case .preDeparture:
                return NSLocalizedString("出发前餐食", comment: "")
            case .inFlight:
                return NSLocalizedString("飞机餐", comment: "")
            case .layover:
                if let airportCode = activePlan.currentSegment?.originCode, !airportCode.isEmpty {
                    return String(format: NSLocalizedString("%@ 转机餐食", comment: ""), airportCode)
                }
                return NSLocalizedString("转机餐食", comment: "")
            case .arrived:
                return NSLocalizedString("到达后餐食", comment: "")
            case .planned, .completed:
                break
            }
        }

        return appViewModel.travelPlans(on: appViewModel.selectedDate).isEmpty
            ? NSLocalizedString("加餐", comment: "")
            : NSLocalizedString("旅行餐食", comment: "")
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
                                    travelAwareTime(
                                        shower.time,
                                        context: shower.travelContext,
                                        fallback: shower.time.map {
                                            appViewModel.displayedShortTime(
                                                for: $0,
                                                recordedTimeZoneIdentifier: shower.timeZoneIdentifier
                                            )
                                        } ?? NSLocalizedString("已记录", comment: ""),
                                        accent: AppTheme.showerAccent,
                                        isCompact: false
                                    )
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    pendingDestructiveAction = .deleteShower(shower)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.warning)
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
                        .foregroundStyle(AppTheme.bowelAccent)
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
                                    travelAwareTime(
                                        entry.time,
                                        context: entry.travelContext,
                                        fallback: entry.time.map {
                                            appViewModel.displayedShortTime(
                                                for: $0,
                                                recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                                            )
                                        } ?? NSLocalizedString("已记录", comment: ""),
                                        accent: AppTheme.bowelAccent,
                                        isCompact: false
                                    )
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    pendingDestructiveAction = .deleteBowelMovement(entry)
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
                        .foregroundStyle(AppTheme.sexualAccent)
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
                                            travelAwareTime(
                                                time,
                                                context: entry.travelContext,
                                                fallback: appViewModel.displayedShortTime(
                                                    for: time,
                                                    recordedTimeZoneIdentifier: entry.timeZoneIdentifier
                                                ),
                                                accent: AppTheme.sexualAccent,
                                                isCompact: false
                                            )
                                        } else {
                                            Text(NSLocalizedString("已记录", comment: ""))
                                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                                .foregroundStyle(AppTheme.sexualAccent)
                                        }
                                        if entry.isMasturbation {
                                            Text(NSLocalizedString("自慰", comment: ""))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(AppTheme.sexualAccent.opacity(0.8))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(AppTheme.sexualAccent.opacity(0.12))
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

    // MARK: - Daily Video

    private var dailyVideoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(NSLocalizedString("每日视频", comment: ""))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }

            if let dailyVideo = appViewModel.dailyRecord.dailyVideo {
                VStack(spacing: 12) {
                    Button {
                        previewingVideoURL = dailyVideo.videoURL
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            VideoContentView(videoURL: dailyVideo.videoURL)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .frame(height: 240)
                                .clipped()

                            Text(videoDurationText(dailyVideo.duration))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.42))
                                .clipShape(Capsule())
                                .padding(12)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 0, maxWidth: .infinity)

                    if appViewModel.canEditSelectedDate {
                        HStack(spacing: 10) {
                            dailyVideoSourceOptionsDialog {
                                Button {
                                    presentDailyVideoSourceOptions()
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text(NSLocalizedString("更换视频", comment: ""))
                                    }
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                pendingDestructiveAction = .deleteDailyVideo
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "trash")
                                    Text(NSLocalizedString("删除视频", comment: ""))
                                }
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.warning)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppTheme.warning.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(18)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppTheme.border.opacity(0.8), lineWidth: 1)
                }
            } else {
                dailyVideoSourceOptionsDialog {
                    Button {
                        presentDailyVideoSourceOptions()
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(NSLocalizedString("添加视频", comment: ""))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                            Text(NSLocalizedString("保存一段最长 10 秒的生活片段", comment: ""))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
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

    private func activeTravelHeaderTitle(_ plan: TravelPlan) -> String {
        guard let segment = plan.currentSegment ?? plan.segments.first else {
            return NSLocalizedString("旅途中", comment: "")
        }

        switch plan.status {
        case .planned:
            return plan.routeSummary
        case .preDeparture:
            return NSLocalizedString("出发前", comment: "")
        case .inFlight:
            return segment.routeTitle
        case .layover:
            return segment.originCode + " " + NSLocalizedString("转机中", comment: "")
        case .arrived:
            return NSLocalizedString("已抵达", comment: "") + " " + (plan.segments.last?.destinationCode ?? plan.routeSummary)
        case .completed:
            return NSLocalizedString("旅程已结束", comment: "")
        }
    }

    private func activeTravelHeaderSubtitle(_ plan: TravelPlan) -> String {
        let total = max(plan.segments.count, 1)
        let index = min((plan.currentSegmentIndex ?? 0) + 1, total)
        guard let segment = plan.currentSegment ?? plan.segments.first else {
            return NSLocalizedString("暂无航段", comment: "")
        }

        switch plan.status {
        case .layover:
            return String(format: NSLocalizedString("下一程第 %d / 共 %d 段 · %@", comment: ""), index, total, segment.flightDisplayTitle)
        case .arrived, .completed:
            return String(format: NSLocalizedString("共 %d 段行程 · %@", comment: ""), total, plan.routeSummary)
        default:
            return String(format: NSLocalizedString("当前第 %d / 共 %d 段 · %@", comment: ""), index, total, segment.flightDisplayTitle)
        }
    }

    private func travelStageSummary(for plan: TravelPlan) -> String {
        guard let segment = plan.currentSegment ?? plan.segments.first else {
            return NSLocalizedString("还没有航段", comment: "")
        }

        switch plan.status {
        case .planned:
            return NSLocalizedString("计划第一程：", comment: "") + segment.flightDisplayTitle
        case .preDeparture:
            return NSLocalizedString("当前：出发前 · ", comment: "") + segment.flightDisplayTitle
        case .inFlight:
            return NSLocalizedString("当前：本程飞行中 · ", comment: "") + segment.flightDisplayTitle
        case .layover:
            return NSLocalizedString("当前：", comment: "")
                + segment.originCode
                + NSLocalizedString(" 转机中 · 下一程 ", comment: "")
                + segment.flightDisplayTitle
        case .arrived:
            return NSLocalizedString("旅程已抵达：", comment: "") + plan.routeSummary
        case .completed:
            return NSLocalizedString("旅程模式已结束：", comment: "") + plan.routeSummary
        }
    }

    private func travelClockText(for plan: TravelPlan, now: Date) -> String {
        guard let segment = plan.currentSegment ?? plan.segments.first else {
            return NSLocalizedString("暂无时间线", comment: "")
        }

        switch plan.status {
        case .planned, .preDeparture:
            return NSLocalizedString("计划起飞：", comment: "")
                + travelDateTimeText(segment.plannedDepartureTime, timeZoneIdentifier: segment.departureTimeZoneIdentifier)
        case .inFlight:
            let elapsed = max(0, now.timeIntervalSince(segment.departureTime))
            return "\(segment.routeTitle) "
                + NSLocalizedString("起飞后 ", comment: "")
                + travelDurationText(elapsed)
                + " · \(segment.originCode) \(now.displayClockTime(in: segment.departureTimeZone)) / \(segment.destinationCode) \(now.displayClockTime(in: segment.arrivalTimeZone))"
        case .layover:
            return "\(segment.originCode) "
                + NSLocalizedString("当地时间 ", comment: "")
                + now.displayClockTime(in: segment.departureTimeZone)
                + " · "
                + NSLocalizedString("下一程 ", comment: "")
                + travelDateTimeText(segment.plannedDepartureTime, timeZoneIdentifier: segment.departureTimeZoneIdentifier)
        case .arrived, .completed:
            return NSLocalizedString("到达时间：", comment: "")
                + travelDateTimeText(segment.arrivalTime, timeZoneIdentifier: segment.arrivalTimeZoneIdentifier)
        }
    }

    private func nextTravelActionTitle(for plan: TravelPlan) -> String {
        switch plan.status {
        case .planned:
            return NSLocalizedString("进入旅行模式", comment: "")
        case .preDeparture, .layover:
            return NSLocalizedString("开始本程", comment: "")
        case .inFlight:
            return NSLocalizedString("已抵达", comment: "")
        case .arrived:
            return NSLocalizedString("结束旅行模式", comment: "")
        case .completed:
            return NSLocalizedString("已结束", comment: "")
        }
    }

    private func travelSegmentTimeSummary(_ segment: TravelSegment) -> String {
        travelDateTimeText(segment.plannedDepartureTime, timeZoneIdentifier: segment.departureTimeZoneIdentifier)
            + " -> "
            + travelDateTimeText(segment.plannedArrivalTime, timeZoneIdentifier: segment.arrivalTimeZoneIdentifier)
    }

    private func travelDateTimeText(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter.string(from: date)
    }

    private func travelDurationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration.rounded() / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
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

    @ViewBuilder
    private func travelAwareTime(
        _ date: Date?,
        context: TravelRecordContext?,
        fallback: String,
        accent: Color,
        isCompact: Bool = true
    ) -> some View {
        if let display = appViewModel.travelTimeDisplay(for: date, context: context) {
            VStack(alignment: isCompact ? .center : .leading, spacing: 2) {
                Text(display.primary)
                    .font(.system(size: isCompact ? 15 : 17, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .lineLimit(2)
                    .multilineTextAlignment(isCompact ? .center : .leading)

                if let secondary = display.secondary {
                    Text(secondary)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .monospacedDigit()
                        .lineLimit(2)
                        .multilineTextAlignment(isCompact ? .center : .leading)
                }
            }
        } else {
            Text(fallback)
                .font(.system(size: isCompact ? 17 : 17, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
    }

    private func openMealEditor(_ meal: MealEntry, with source: MealCaptureMode) {
        DispatchQueue.main.async {
            editingMealContext = MealEditorContext(entry: meal, preferredSource: source)
        }
    }

    private func presentDailyVideoSourceOptions() {
        guard appViewModel.canEditSelectedDate else { return }
        showingDailyVideoSourceOptions = true
    }

    private func dailyVideoSourceOptionsDialog<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .confirmationDialog(NSLocalizedString("每日视频", comment: ""), isPresented: $showingDailyVideoSourceOptions) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(NSLocalizedString("录制视频", comment: "")) {
                        openDailyVideoPicker(.camera)
                    }
                }
                Button(NSLocalizedString("选择相册视频", comment: "")) {
                    openDailyVideoPicker(.photoLibrary)
                }
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            }
    }

    private func openDailyVideoPicker(_ source: UIImagePickerController.SourceType) {
        guard appViewModel.canEditSelectedDate else { return }
        guard source != .camera || UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        videoPickerSource = source
    }

    private func videoDurationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "00:%02d", min(seconds, 59))
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
        case .deleteDailyVideo:
            Task { await appViewModel.deleteDailyVideo() }
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

private struct TravelTimelineItem: Identifiable {
    let id: String
    let title: String
    let date: Date?
    let context: TravelRecordContext?
    let fallback: String
    let accent: Color
    let systemImage: String
    let note: String?
}

enum TravelEditorContext: Identifiable {
    case new
    case edit(TravelPlan)

    var id: String {
        switch self {
        case .new:
            return "new-travel"
        case .edit(let plan):
            return plan.id.uuidString
        }
    }

    var plan: TravelPlan? {
        switch self {
        case .new:
            return nil
        case .edit(let plan):
            return plan
        }
    }
}

enum TravelSleepEditorContext: Identifiable {
    case new(TravelPlan)
    case edit(TravelPlan, TravelSleepSession)

    var id: String {
        switch self {
        case .new(let plan):
            return "new-travel-sleep-\(plan.id.uuidString)"
        case .edit(_, let session):
            return session.id.uuidString
        }
    }

    var plan: TravelPlan {
        switch self {
        case .new(let plan), .edit(let plan, _):
            return plan
        }
    }

    var session: TravelSleepSession? {
        switch self {
        case .new:
            return nil
        case .edit(_, let session):
            return session
        }
    }
}

private enum TravelSleepTimeInputMode: String, CaseIterable, Identifiable {
    case origin
    case destination
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .origin: NSLocalizedString("出发地", comment: "")
        case .destination: NSLocalizedString("目的地", comment: "")
        case .device: NSLocalizedString("手机", comment: "")
        }
    }
}

private struct TravelSleepSessionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var title: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var note: String
    @State private var inputMode: TravelSleepTimeInputMode
    @State private var showingDeleteConfirmation = false

    let plan: TravelPlan
    let session: TravelSleepSession?
    let onSave: (TravelSleepSession, TravelPlan) -> Void
    let onDelete: (() -> Void)?

    init(
        plan: TravelPlan,
        session: TravelSleepSession?,
        onSave: @escaping (TravelSleepSession, TravelPlan) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        let seed = session ?? Self.defaultSession(for: plan)
        self.plan = plan
        self.session = session
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: seed.title)
        _startTime = State(initialValue: seed.startTime)
        _endTime = State(initialValue: seed.endTime)
        _note = State(initialValue: seed.note ?? "")
        _inputMode = State(initialValue: .origin)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    TextField(NSLocalizedString("名称，例如 飞机小睡", comment: ""), text: $title)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("时间记录方式", comment: ""))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)

                        Picker("", selection: $inputMode) {
                            ForEach(TravelSleepTimeInputMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    timeBlock(
                        title: NSLocalizedString("开始", comment: ""),
                        date: $startTime,
                        accent: AppTheme.sleepAccent
                    )

                    timeBlock(
                        title: NSLocalizedString("醒来", comment: ""),
                        date: $endTime,
                        accent: AppTheme.wakeAccent
                    )

                    RecordNoteSection(note: $note)

                    if onDelete != nil {
                        Button(NSLocalizedString("删除睡眠记录", comment: ""), role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("旅行睡眠", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        onSave(makeSession(), plan)
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("删除睡眠记录？", comment: ""), isPresented: $showingDeleteConfirmation) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("删除", comment: ""), role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("此操作无法撤销。", comment: ""))
            }
        }
    }

    private func timeBlock(title: String, date: Binding<Date>, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(timePreview(for: date.wrappedValue))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }

            DatePicker(
                "",
                selection: date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .environment(\.timeZone, selectedTimeZone)
        }
        .padding(16)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectedSegment: TravelSegment? {
        if let segmentID = session?.segmentID,
           let segment = plan.segments.first(where: { $0.id == segmentID }) {
            return segment
        }
        return plan.currentSegment ?? plan.segments.first
    }

    private var effectivePhase: TravelPlanStatus {
        session?.phase ?? (plan.status == .planned ? .preDeparture : plan.status)
    }

    private var travelContext: TravelRecordContext {
        TravelRecordContext(
            planID: plan.id,
            segmentID: selectedSegment?.id,
            phase: effectivePhase
        )
    }

    private var selectedTimeZone: TimeZone {
        guard let segment = selectedSegment else { return .autoupdatingCurrent }
        switch inputMode {
        case .origin:
            return segment.departureTimeZone
        case .destination:
            return segment.arrivalTimeZone
        case .device:
            return .autoupdatingCurrent
        }
    }

    private func timePreview(for date: Date) -> String {
        appViewModel.travelTimeText(for: date, context: travelContext)
            ?? date.displayClockTime(in: selectedTimeZone)
    }

    private func makeSession() -> TravelSleepSession {
        TravelSleepSession(
            id: session?.id ?? UUID(),
            segmentID: selectedSegment?.id,
            phase: effectivePhase,
            title: title,
            startTime: startTime,
            endTime: max(startTime, endTime),
            timeZoneIdentifier: selectedTimeZone.identifier,
            source: .manual,
            note: note
        )
    }

    private static func defaultSession(for plan: TravelPlan) -> TravelSleepSession {
        let end = Date()
        let start = end.addingTimeInterval(-45 * 60)
        let segment = plan.currentSegment ?? plan.segments.first
        let phase: TravelPlanStatus = plan.status == .planned ? .preDeparture : plan.status
        let timeZoneIdentifier: String? = {
            guard let segment else { return TimeZone.autoupdatingCurrent.identifier }
            switch phase {
            case .arrived, .completed:
                return segment.arrivalTimeZoneIdentifier
            case .planned, .preDeparture, .inFlight, .layover:
                return segment.departureTimeZoneIdentifier
            }
        }()

        return TravelSleepSession(
            segmentID: segment?.id,
            phase: phase,
            title: NSLocalizedString("小睡", comment: ""),
            startTime: start,
            endTime: end,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private struct TravelPlanEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var segments: [TravelSegmentDraft]
    @State private var showingDeleteConfirmation = false

    let plan: TravelPlan?
    let onSave: (TravelPlan) -> Void
    let onDelete: (() -> Void)?

    init(plan: TravelPlan?, onSave: @escaping (TravelPlan) -> Void, onDelete: (() -> Void)? = nil) {
        self.plan = plan
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: plan?.title ?? "")
        _segments = State(initialValue: plan?.segments.map(TravelSegmentDraft.init(segment:)) ?? [
            TravelSegmentDraft()
        ])
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("旅程名称", comment: ""))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField(NSLocalizedString("例如 BOS-PKX 旅程", comment: ""), text: $title)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(AppTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            loadSamplePlan()
                        } label: {
                            Label(NSLocalizedString("填入 BOS-PKX 示例", comment: ""), systemImage: "airplane")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(AppTheme.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canReplaceSegments)
                        .opacity(canReplaceSegments ? 1 : 0.45)
                    }
                    .padding(16)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                    }

                    ForEach($segments) { $segment in
                        TravelSegmentDraftCard(
                            segment: $segment,
                            isLocked: lockedSegmentIDs.contains(segment.id),
                            canDelete: segments.count > 1,
                            onDelete: {
                                segments.removeAll { $0.id == segment.id }
                            }
                        )
                    }

                    Button {
                        appendSegment()
                    } label: {
                        Label(NSLocalizedString("添加航段", comment: ""), systemImage: "plus")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAppendSegment)
                    .opacity(canAppendSegment ? 1 : 0.45)

                    if onDelete != nil {
                        Button {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(NSLocalizedString("删除旅行计划", comment: ""), systemImage: "trash")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.warning)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.warning.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(plan == nil ? NSLocalizedString("添加旅行", comment: "") : NSLocalizedString("编辑旅行", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        onSave(makePlan())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(NSLocalizedString("删除旅行计划？", comment: ""), isPresented: $showingDeleteConfirmation) {
                Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("删除旅行计划", comment: ""), role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("此操作会删除整个旅行计划，且无法撤销。", comment: ""))
            }
        }
    }

    private var canSave: Bool {
        !segments.isEmpty
            && segments.allSatisfy {
                AirportCatalog.airport(for: $0.originCode) != nil
                    && AirportCatalog.airport(for: $0.destinationCode) != nil
            }
    }

    private var lockedSegmentIDs: Set<UUID> {
        guard let plan,
              let currentIndex = plan.currentSegmentIndex else {
            return []
        }

        switch plan.status {
        case .planned, .preDeparture:
            return []
        case .layover:
            return Set(plan.segments.prefix(currentIndex).map(\.id))
        case .inFlight:
            return Set(plan.segments.prefix(currentIndex + 1).map(\.id))
        case .arrived, .completed:
            return Set(plan.segments.map(\.id))
        }
    }

    private var canReplaceSegments: Bool {
        guard let plan else { return true }
        return plan.status == .planned || plan.status == .preDeparture
    }

    private var canAppendSegment: Bool {
        guard let plan else { return true }
        switch plan.status {
        case .planned, .preDeparture, .layover:
            return true
        case .inFlight, .arrived, .completed:
            return false
        }
    }

    private func makePlan() -> TravelPlan {
        let savedSegments = segments.map { $0.makeSegment() }
        let fallbackTitle = routeTitle(for: savedSegments)
        let resolvedCurrentSegmentID = plan?.currentSegmentID.flatMap { currentID in
            savedSegments.contains { $0.id == currentID } ? currentID : nil
        }
        return TravelPlan(
            id: plan?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : title,
            segments: savedSegments,
            sleepSessions: plan?.sleepSessions ?? [],
            status: plan?.status ?? .planned,
            currentSegmentID: resolvedCurrentSegmentID,
            createdAt: plan?.createdAt ?? .now,
            modifiedAt: .now
        )
    }

    private func routeTitle(for segments: [TravelSegment]) -> String {
        guard let first = segments.first, let last = segments.last else {
            return NSLocalizedString("未命名旅程", comment: "")
        }
        return "\(first.originCode)-\(last.destinationCode) 旅程"
    }

    private func appendSegment() {
        if let last = segments.last {
            segments.append(TravelSegmentDraft(after: last))
        } else {
            segments.append(TravelSegmentDraft())
        }
    }

    private func loadSamplePlan() {
        let sample = TravelPlan.sampleBOSPKX()
        title = sample.title
        segments = sample.segments.map(TravelSegmentDraft.init(segment:))
    }
}

private struct TravelSegmentDraftCard: View {
    @Binding var segment: TravelSegmentDraft
    @State private var showingDeleteConfirmation = false

    let isLocked: Bool
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.routeTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                }
                Spacer()
                if canDelete && !isLocked {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.warning)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.warning.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Text(NSLocalizedString("航班号", comment: ""))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 54, alignment: .leading)
                TextField(NSLocalizedString("例如 BA238", comment: ""), text: $segment.flightNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AirportSearchField(
                title: NSLocalizedString("起飞机场", comment: ""),
                placeholder: NSLocalizedString("输入 BOS / Boston / Logan", comment: ""),
                airportCode: $segment.originCode,
                timeZoneIdentifier: $segment.departureTimeZoneIdentifier,
                isLocked: isLocked
            )

            travelDatePicker(
                title: NSLocalizedString("起飞时间", comment: ""),
                systemImage: "airplane.departure",
                date: $segment.departureDate,
                airport: segment.originAirport,
                timeZoneIdentifier: segment.resolvedDepartureTimeZoneIdentifier
            )

            AirportSearchField(
                title: NSLocalizedString("降落机场", comment: ""),
                placeholder: NSLocalizedString("输入 PKX / Beijing / Daxing", comment: ""),
                airportCode: $segment.destinationCode,
                timeZoneIdentifier: $segment.arrivalTimeZoneIdentifier,
                isLocked: isLocked
            )

            travelDatePicker(
                title: NSLocalizedString("到达时间", comment: ""),
                systemImage: "airplane.arrival",
                date: $segment.arrivalDate,
                airport: segment.destinationAirport,
                timeZoneIdentifier: segment.resolvedArrivalTimeZoneIdentifier
            )
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.62 : 1)
        .alert(NSLocalizedString("删除航段？", comment: ""), isPresented: $showingDeleteConfirmation) {
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("删除航段", comment: ""), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("此操作会从当前旅行计划里移除这一航段。", comment: ""))
        }
    }

    private func travelDatePicker(
        title: String,
        systemImage: String,
        date: Binding<Date>,
        airport: AirportInfo?,
        timeZoneIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.timeZone, TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent)

            Text(timeZoneSummary(for: airport, timeZoneIdentifier: timeZoneIdentifier, at: date.wrappedValue))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(13)
        .background(AppTheme.elevatedSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func timeZoneSummary(for airport: AirportInfo?, timeZoneIdentifier: String, at date: Date) -> String {
        let city = airport?.city ?? NSLocalizedString("当地", comment: "")
        return city + " · " + TimeZoneDisplay.userFacingTimeZoneText(for: timeZoneIdentifier, at: date)
    }
}

#if DEBUG
private struct TravelPlanDebugPanelSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plans: [TravelPlan]
    let preferences: UserPreferences
    let selectedDate: Date
    let onStartHypotheticalTravel: () -> Void
    let onClearHypotheticalTravel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    debugActions
                    debugSummary

                    if plans.isEmpty {
                        Text("当前没有旅行计划")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        ForEach(plans) { plan in
                            TravelPlanDebugPlanCard(plan: plan, preferences: preferences)
                        }
                    }
                }
                .padding(18)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("旅行测试面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var debugActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("测试操作")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Button {
                onStartHypotheticalTravel()
            } label: {
                Label("启动假想旅行（现在）", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.actionFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                onClearHypotheticalTravel()
            } label: {
                Label("清除假想旅行", systemImage: "trash")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
        }
    }

    private var debugSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前选择日：\(selectedDate.storageKey())")
            Text("午夜模式：\(preferences.midnightMode.isEnabled ? "开启" : "关闭") · cutoff \(MidnightModeSettings.fixedCutoffHour):00")
            Text("旅行计划数量：\(plans.count)")
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct TravelPlanDebugPlanCard: View {
    @Environment(\.locale) private var locale

    let plan: TravelPlan
    let preferences: UserPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accentSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("旅行数据")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(plan.displayTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                Label("logical \(dateCoverageText)", systemImage: "calendar")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())

                Text("\(plan.segments.count) " + NSLocalizedString("段", comment: ""))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
            }

            debugKeyBlock

            stageStrip

            VStack(spacing: 8) {
                ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                    previewSegmentRow(segment, index: index)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
        }
    }

    private var debugKeyBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("affectedStorageKeys")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Text(plan.affectedStorageKeys(using: preferences).sorted().joined(separator: ", "))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("legacyNaturalKeys")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            Text(plan.affectedStorageKeys.sorted().joined(separator: ", "))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(AppTheme.elevatedSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var stageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                previewStagePill(NSLocalizedString("出发前", comment: ""), isPrimary: true)
                ForEach(Array(plan.segments.enumerated()), id: \.element.id) { index, segment in
                    previewStagePill(segment.routeTitle, isPrimary: true)
                    if index < plan.segments.count - 1 {
                        previewStagePill(NSLocalizedString("转机", comment: ""), isPrimary: false)
                    }
                }
                previewStagePill(NSLocalizedString("抵达", comment: ""), isPrimary: true)
            }
            .padding(.vertical, 2)
        }
    }

    private func previewStagePill(_ title: String, isPrimary: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isPrimary ? AppTheme.accent : AppTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isPrimary ? AppTheme.accentSoft : AppTheme.mutedFill)
            .clipShape(Capsule())
    }

    private func previewSegmentRow(_ segment: TravelSegment, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(segment.flightDisplayTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(segmentPreviewTimeText(segment))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(segmentDebugKeyText(segment))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(durationText(segment.plannedDuration))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .monospacedDigit()
        }
        .padding(12)
        .background(AppTheme.elevatedSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dateCoverageText: String {
        let keys = plan.affectedStorageKeys(using: preferences).sorted()
        guard let first = keys.first else { return NSLocalizedString("无日期", comment: "") }
        guard let last = keys.last, last != first else { return formattedStorageKey(first) }
        return formattedStorageKey(first) + " - " + formattedStorageKey(last)
    }

    private func segmentPreviewTimeText(_ segment: TravelSegment) -> String {
        "\(segment.originCode) \(localDateTime(segment.plannedDepartureTime, in: segment.departureTimeZoneIdentifier))"
            + " -> "
            + "\(segment.destinationCode) \(localDateTime(segment.plannedArrivalTime, in: segment.arrivalTimeZoneIdentifier))"
    }

    private func segmentDebugKeyText(_ segment: TravelSegment) -> String {
        let departureKey = preferences.storageKey(
            for: segment.plannedDepartureTime,
            timeZoneIdentifier: segment.departureTimeZoneIdentifier,
            fallbackTimeZone: segment.departureTimeZone
        )
        let arrivalKey = preferences.storageKey(
            for: segment.plannedArrivalTime,
            timeZoneIdentifier: segment.arrivalTimeZoneIdentifier,
            fallbackTimeZone: segment.arrivalTimeZone
        )
        return "depKey \(departureKey) / arrKey \(arrivalKey)"
    }

    private func localDateTime(_ date: Date, in timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter.string(from: date)
            + " "
            + TimeZoneDisplay.utcOffsetText(for: timeZoneIdentifier, at: date)
    }

    private func formattedStorageKey(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return key
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration.rounded() / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }
}

#endif

private struct AirportSearchField: View {
    let title: String
    let placeholder: String
    @Binding var airportCode: String
    @Binding var timeZoneIdentifier: String
    let isLocked: Bool

    @State private var searchText = ""
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                if let selectedAirport, !isSearching {
                    selectedAirportButton(selectedAirport)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField(placeholder, text: $searchText)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .disabled(isLocked)
                    }

                    if selectedAirport == nil,
                       !airportCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(NSLocalizedString("请选择列表中的机场", comment: ""))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.warning)
                    }

                    if !searchResults.isEmpty && !isLocked {
                        VStack(spacing: 0) {
                            ForEach(searchResults) { airport in
                                Button {
                                    select(airport, clearsSearch: true)
                                } label: {
                                    airportResultRow(airport)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
                        }
                    }
                }
            }
            .padding(13)
            .background(AppTheme.elevatedSurface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onAppear {
            syncSelectedAirport()
            isSearching = selectedAirport == nil
        }
        .onChange(of: airportCode) { _, _ in
            syncSelectedAirport()
            if selectedAirport != nil {
                isSearching = false
            }
        }
        .onChange(of: searchText) { _, newValue in
            selectExactAirportIfNeeded(newValue)
        }
    }

    private var selectedAirport: AirportInfo? {
        AirportCatalog.airport(for: airportCode)
    }

    private var searchResults: [AirportInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if selectedAirport?.code == query.uppercased() {
            return []
        }
        return AirportCatalog.search(query, limit: 7)
    }

    private func selectedAirportButton(_ airport: AirportInfo) -> some View {
        Button {
            guard !isLocked else { return }
            searchText = ""
            isSearching = true
        } label: {
            HStack(alignment: .center, spacing: 10) {
                selectedAirportView(airport)

                Spacer(minLength: 8)

                if !isLocked {
                    Text(NSLocalizedString("更改", comment: ""))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.accentSoft)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private func selectedAirportView(_ airport: AirportInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(airport.code)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .monospaced()
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(airport.city)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(airport.detailText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    private func airportResultRow(_ airport: AirportInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(airport.code)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .monospaced()
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(airport.city)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(airport.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Text(TimeZoneDisplay.userFacingTimeZoneText(for: airport.timeZoneIdentifier))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func selectExactAirportIfNeeded(_ text: String) {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3,
              let airport = AirportCatalog.airport(for: code) else {
            return
        }
        select(airport, clearsSearch: false)
    }

    private func select(_ airport: AirportInfo, clearsSearch: Bool) {
        airportCode = airport.code
        timeZoneIdentifier = airport.timeZoneIdentifier
        if clearsSearch {
            searchText = ""
        }
        isSearching = false
    }

    private func syncSelectedAirport() {
        guard let selectedAirport else { return }
        timeZoneIdentifier = selectedAirport.timeZoneIdentifier
    }
}

private struct TravelSegmentDraft: Identifiable {
    var id: UUID
    var flightNumber: String
    var originCode: String
    var destinationCode: String
    var departureDate: Date
    var arrivalDate: Date
    var departureTimeZoneIdentifier: String
    var arrivalTimeZoneIdentifier: String
    var actualDepartureTime: Date?
    var actualArrivalTime: Date?

    init(
        id: UUID = UUID(),
        flightNumber: String = "",
        originCode: String = "BOS",
        destinationCode: String = "LHR",
        departureDate: Date = Date().addingTimeInterval(86_400).settingTime(hour: 9, minute: 0),
        arrivalDate: Date = Date().addingTimeInterval(86_400).settingTime(hour: 17, minute: 0),
        departureTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        arrivalTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        actualDepartureTime: Date? = nil,
        actualArrivalTime: Date? = nil
    ) {
        self.id = id
        self.flightNumber = flightNumber
        self.originCode = Self.normalizedAirportCode(originCode)
        self.destinationCode = Self.normalizedAirportCode(destinationCode)
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.departureTimeZoneIdentifier = AirportCatalog.airport(for: originCode)?.timeZoneIdentifier ?? departureTimeZoneIdentifier
        self.arrivalTimeZoneIdentifier = AirportCatalog.airport(for: destinationCode)?.timeZoneIdentifier ?? arrivalTimeZoneIdentifier
        self.actualDepartureTime = actualDepartureTime
        self.actualArrivalTime = actualArrivalTime
    }

    init(segment: TravelSegment) {
        self.init(
            id: segment.id,
            flightNumber: segment.flightNumber ?? "",
            originCode: segment.originCode,
            destinationCode: segment.destinationCode,
            departureDate: Self.editorDate(from: segment.plannedDepartureTime, timeZoneIdentifier: segment.departureTimeZoneIdentifier),
            arrivalDate: Self.editorDate(from: segment.plannedArrivalTime, timeZoneIdentifier: segment.arrivalTimeZoneIdentifier),
            departureTimeZoneIdentifier: segment.departureTimeZoneIdentifier,
            arrivalTimeZoneIdentifier: segment.arrivalTimeZoneIdentifier,
            actualDepartureTime: segment.actualDepartureTime,
            actualArrivalTime: segment.actualArrivalTime
        )
    }

    init(after previous: TravelSegmentDraft) {
        self.init(
            originCode: previous.destinationCode,
            destinationCode: "",
            departureDate: previous.arrivalDate.addingTimeInterval(2 * 3600),
            arrivalDate: previous.arrivalDate.addingTimeInterval(10 * 3600),
            departureTimeZoneIdentifier: previous.arrivalTimeZoneIdentifier,
            arrivalTimeZoneIdentifier: previous.arrivalTimeZoneIdentifier
        )
    }

    var routeTitle: String {
        let origin = Self.normalizedAirportCode(originCode)
        let destination = Self.normalizedAirportCode(destinationCode)
        if origin.isEmpty && destination.isEmpty {
            return NSLocalizedString("新航段", comment: "")
        }
        return "\(origin.isEmpty ? "--" : origin)-\(destination.isEmpty ? "--" : destination)"
    }

    var normalizedFlightNumber: String? {
        let trimmed = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    var originAirport: AirportInfo? {
        AirportCatalog.airport(for: originCode)
    }

    var destinationAirport: AirportInfo? {
        AirportCatalog.airport(for: destinationCode)
    }

    var resolvedDepartureTimeZoneIdentifier: String {
        originAirport?.timeZoneIdentifier ?? departureTimeZoneIdentifier
    }

    var resolvedArrivalTimeZoneIdentifier: String {
        destinationAirport?.timeZoneIdentifier ?? arrivalTimeZoneIdentifier
    }

    func makeSegment() -> TravelSegment {
        TravelSegment(
            id: id,
            flightNumber: normalizedFlightNumber,
            originCode: Self.normalizedAirportCode(originCode),
            destinationCode: Self.normalizedAirportCode(destinationCode),
            plannedDepartureTime: Self.absoluteDate(from: departureDate, timeZoneIdentifier: resolvedDepartureTimeZoneIdentifier),
            plannedArrivalTime: Self.absoluteDate(from: arrivalDate, timeZoneIdentifier: resolvedArrivalTimeZoneIdentifier),
            departureTimeZoneIdentifier: resolvedDepartureTimeZoneIdentifier,
            arrivalTimeZoneIdentifier: resolvedArrivalTimeZoneIdentifier,
            actualDepartureTime: actualDepartureTime,
            actualArrivalTime: actualArrivalTime
        )
    }

    private static func normalizedAirportCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func editorDate(from date: Date, timeZoneIdentifier: String) -> Date {
        let sourceTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let components = sourceCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return Calendar.current.date(from: components) ?? date
    }

    private static func absoluteDate(from editorDate: Date, timeZoneIdentifier: String) -> Date {
        let targetTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: editorDate)
        var targetCalendar = Calendar(identifier: .gregorian)
        targetCalendar.timeZone = targetTimeZone
        return targetCalendar.date(from: DateComponents(
            timeZone: targetTimeZone,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: components.minute
        )) ?? editorDate
    }
}

private enum PendingDestructiveAction: Identifiable {
    case removeMealPhoto(MealEntry)
    case deleteMeal(MealEntry)
    case clearMealRecord(MealEntry)
    case deleteShower(ShowerEntry)
    case deleteBowelMovement(BowelMovementEntry)
    case deleteSexualActivity(SexualActivityEntry)
    case deleteDailyVideo

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
        case .deleteDailyVideo:
            return "delete-daily-video"
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
        case .deleteDailyVideo:
            return NSLocalizedString("删除视频？", comment: "")
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
        case .deleteDailyVideo:
            return NSLocalizedString("此操作会移除今天的视频片段，且无法撤销。", comment: "")
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
        case .deleteDailyVideo:
            return NSLocalizedString("删除视频", comment: "")
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

private struct IdentifiableVideo: Identifiable {
    let id = UUID()
    let url: String
}

struct PhotoPreviewOverlay: View {
    let photoURL: String
    let onDismiss: () -> Void

    @State private var isSavingToLibrary = false
    @State private var didSaveToLibrary = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

                PhotoContentView(photoURL: photoURL, contentMode: .fit)
                    .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            mediaSaveButton(
                isSaving: isSavingToLibrary,
                didSave: didSaveToLibrary,
                action: savePhotoToLibrary
            )
            .padding(.top, 54)
            .padding(.trailing, 18)
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
        .alert(NSLocalizedString("保存失败", comment: ""), isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button(NSLocalizedString("知道了", comment: ""), role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func savePhotoToLibrary() {
        guard !isSavingToLibrary else { return }
        didSaveToLibrary = false
        isSavingToLibrary = true

        Task {
            do {
                try await MediaLibrarySaver.savePhoto(from: photoURL)
                didSaveToLibrary = true
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSavingToLibrary = false
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
