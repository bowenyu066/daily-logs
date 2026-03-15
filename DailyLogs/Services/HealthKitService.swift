import Foundation
import HealthKit

@MainActor
final class HealthKitService: HealthSyncAdapter {
    private let store = HKHealthStore()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let sleepType = HKCategoryType(.sleepAnalysis)
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func fetchSleepData(for date: Date, after registrationDate: Date) async throws -> SleepRecord? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        guard date >= registrationDate.startOfDay else { return nil }

        let calendar = Calendar.current
        let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
        let queryStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay)!
        let queryEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!

        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                }
            }
            store.execute(query)
        }

        let sleepSamples = samples.filter { sample in
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            return value == .asleepCore || value == .asleepDeep || value == .asleepREM || value == .awake || value == .asleepUnspecified
        }

        guard !sleepSamples.isEmpty else { return nil }

        // Group samples into contiguous sessions (gap > 30 min = separate session)
        let sessions = groupIntoSessions(sleepSamples)

        // Pick the main overnight session: the longest session that starts after 20:00 or before 06:00
        let mainSession = pickOvernightSession(sessions, date: date)
        guard !mainSession.isEmpty else { return nil }

        let asleepSamples = mainSession.filter { sample in
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            return value != .awake
        }

        let bedtime = asleepSamples.map(\.startDate).min()
        let wakeTime = asleepSamples.map(\.endDate).max()

        let stageIntervals = mainSession.compactMap { sample -> SleepStageInterval? in
            guard let stage = mapStage(sample.value) else { return nil }
            return SleepStageInterval(stage: stage, start: sample.startDate, end: sample.endDate)
        }

        return SleepRecord(
            bedtimePreviousNight: bedtime,
            wakeTimeCurrentDay: wakeTime,
            source: .healthKit,
            stageIntervals: stageIntervals
        )
    }

    private func groupIntoSessions(_ samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var currentEnd: Date = .distantPast

        for sample in sorted {
            if current.isEmpty || sample.startDate.timeIntervalSince(currentEnd) <= 30 * 60 {
                current.append(sample)
                currentEnd = max(currentEnd, sample.endDate)
            } else {
                sessions.append(current)
                current = [sample]
                currentEnd = sample.endDate
            }
        }
        if !current.isEmpty {
            sessions.append(current)
        }
        return sessions
    }

    private func pickOvernightSession(_ sessions: [[HKCategorySample]], date: Date) -> [HKCategorySample] {
        let calendar = Calendar.current
        // The "night boundary" is roughly 20:00 previous day to 10:00 current day
        let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
        let nightStart = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: previousDay)!
        let nightEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)!

        // Filter to sessions that overlap with the nighttime window
        let nightSessions = sessions.filter { session in
            guard let first = session.first, let last = session.last else { return false }
            let sessionStart = first.startDate
            let sessionEnd = last.endDate
            // Must overlap with night window
            return sessionStart < nightEnd && sessionEnd > nightStart
        }

        // Pick the longest session
        if let longest = nightSessions.max(by: { sessionDuration($0) < sessionDuration($1) }) {
            return longest
        }

        // Fallback: return the longest session overall
        return sessions.max(by: { sessionDuration($0) < sessionDuration($1) }) ?? []
    }

    private func sessionDuration(_ session: [HKCategorySample]) -> TimeInterval {
        guard let first = session.first, let last = session.last else { return 0 }
        return last.endDate.timeIntervalSince(first.startDate)
    }

    private func mapStage(_ value: Int) -> SleepStage? {
        guard let sleepValue = HKCategoryValueSleepAnalysis(rawValue: value) else { return nil }
        switch sleepValue {
        case .asleepCore, .asleepUnspecified:
            return .light
        case .asleepDeep:
            return .deep
        case .asleepREM:
            return .rem
        case .awake:
            return .awake
        default:
            return nil
        }
    }
}
