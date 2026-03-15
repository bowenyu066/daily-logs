import Foundation
import HealthKit

final class HealthKitService: HealthSyncAdapter {
    private let store = HKHealthStore()

    func latestSleepSourceHint() -> RecordSource? {
        HKHealthStore.isHealthDataAvailable() ? .healthKit : nil
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let sleepType = HKCategoryType(.sleepAnalysis)
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func fetchSleepData(for date: Date, after registrationDate: Date) async throws -> SleepRecord? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        guard date >= registrationDate.startOfDay else { return nil }

        let calendar = Calendar.current
        let queryStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: date)!)!
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

        let asleepSamples = sleepSamples.filter { sample in
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            return value != .awake
        }

        let bedtime = asleepSamples.map(\.startDate).min()
        let wakeTime = asleepSamples.map(\.endDate).max()

        let stageIntervals = sleepSamples.compactMap { sample -> SleepStageInterval? in
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
