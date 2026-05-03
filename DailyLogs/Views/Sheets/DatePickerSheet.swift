import SwiftUI

struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var draftDate: Date
    @State private var visibleMonth: Date
    let allowedRange: ClosedRange<Date>
    let onConfirm: (Date) -> Void

    init(selectedDate: Date, allowedRange: ClosedRange<Date>, onConfirm: @escaping (Date) -> Void) {
        let normalizedDate = selectedDate.startOfDay
        _draftDate = State(initialValue: normalizedDate)
        _visibleMonth = State(initialValue: Calendar.current.dateInterval(of: .month, for: normalizedDate)?.start ?? normalizedDate)
        self.allowedRange = allowedRange
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                monthHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                RingMonthCalendar(
                    visibleMonth: visibleMonth,
                    selectedDate: draftDate,
                    allowedRange: allowedRange,
                    locale: locale,
                    reportForDate: { appViewModel.displayedDailyInsightReport(for: $0) },
                    onSelect: { draftDate = $0 }
                )
                .padding(.horizontal, 18)

                Spacer()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("选择日期", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("确定", comment: "")) {
                        onConfirm(draftDate.startOfDay)
                        dismiss()
                    }
                }
            }
        }
        .environment(\.locale, locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }

    private var monthHeader: some View {
        HStack(spacing: 14) {
            Button {
                visibleMonth = month(byAdding: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: -1))
            .opacity(canMoveMonth(by: -1) ? 1 : 0.35)

            Spacer()

            Text(monthTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            Button {
                visibleMonth = month(byAdding: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: 1))
            .opacity(canMoveMonth(by: 1) ? 1 : 0.35)
        }
        .foregroundStyle(AppTheme.primaryText)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    private func month(byAdding value: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func canMoveMonth(by value: Int) -> Bool {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month(byAdding: value)) else { return false }
        return interval.end > allowedRange.lowerBound.startOfDay && interval.start <= allowedRange.upperBound.startOfDay
    }
}

private struct RingMonthCalendar: View {
    let visibleMonth: Date
    let selectedDate: Date
    let allowedRange: ClosedRange<Date>
    let locale: Locale
    let reportForDate: (Date) -> DailyInsightReport?
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(height: 26)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cellDate in
                    if let cellDate {
                        dayCell(for: cellDate)
                    } else {
                        Color.clear
                            .frame(height: 64)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func dayCell(for date: Date) -> some View {
        let normalizedDate = date.startOfDay
        let isSelected = Calendar.current.isDate(normalizedDate, inSameDayAs: selectedDate)
        let isAllowed = allowedRange.contains(normalizedDate)

        return Button {
            guard isAllowed else { return }
            onSelect(normalizedDate)
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 24, height: 24)
                    }

                    Text("\(Calendar.current.component(.day, from: normalizedDate))")
                        .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : AppTheme.primaryText)
                        .monospacedDigit()
                }
                .frame(height: 21)

                DailyInsightMiniRings(report: reportForDate(normalizedDate), isMuted: !isAllowed)
                    .frame(width: 40, height: 40)
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .opacity(isAllowed ? 1 : 0.28)
        }
        .buttonStyle(.plain)
        .disabled(!isAllowed)
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }

        let leadingBlanks = max(0, interval.start.isoWeekday - 1)
        var cells = Array<Date?>(repeating: nil, count: leadingBlanks)
        cells += dayRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...6]) + [symbols[0]]
    }
}

private struct DailyInsightMiniRings: View {
    let report: DailyInsightReport?
    let isMuted: Bool

    private let lineWidth: CGFloat = 4.8
    private let ringGap: CGFloat = 12.0
    private let outerSize: CGFloat = 36

    private var rings: [DailyInsightMiniRingMetric] {
        guard let report else { return [] }

        let sleep = report.components.first(where: { $0.kind == .sleep }).map {
            DailyInsightMiniRingMetric(progress: $0.scoreRatio, color: Color(red: 0.00, green: 0.48, blue: 1.00))
        }
        let meals = report.components.first(where: { $0.kind == .meals }).map {
            DailyInsightMiniRingMetric(progress: $0.scoreRatio, color: Color(red: 0.55, green: 0.88, blue: 0.00))
        }
        let careComponents = report.components.filter { $0.kind == .shower || $0.kind == .bowelMovement }
        let careProgress = careComponents.isEmpty ? nil : careComponents.map(\.scoreRatio).reduce(0, +) / Double(careComponents.count)
        let care = careProgress.map {
            DailyInsightMiniRingMetric(progress: $0, color: Color(red: 1.00, green: 0.16, blue: 0.36))
        }

        return [care, meals, sleep].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                Circle()
                    .stroke(ring.color.opacity(isMuted ? 0.14 : 0.30), lineWidth: lineWidth)
                    .frame(width: ringSize(for: index), height: ringSize(for: index))

                Circle()
                    .trim(from: 0.001, to: max(CGFloat(ring.progress), 0.001))
                    .stroke(
                        ring.color.opacity(isMuted ? 0.44 : 1.0),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize(for: index), height: ringSize(for: index))
                    .shadow(color: ring.color.opacity(isMuted ? 0 : 0.10), radius: 0.8, x: 0, y: 0)
            }
        }
    }

    private func ringSize(for index: Int) -> CGFloat {
        max(8, outerSize - CGFloat(index) * ringGap)
    }
}

private struct DailyInsightMiniRingMetric {
    let progress: Double
    let color: Color
}
