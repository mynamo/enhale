import Foundation
import HealthKit
import EnhaleCore

/// Reads workouts, sleep, and daily activity/vitals from HealthKit and maps
/// them into the backend's health DTOs. HealthKit is on-device only — this is
/// the native layer that a web/Android client would each implement differently
/// (Health Connect on Android) against the same `HealthSyncRequest` contract.
///
/// Note: HealthKit returns no data in the iOS Simulator — test on a real device
/// with Apple Watch / Health data.
@MainActor
final class HealthKitService: ObservableObject {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis)]
        let quantities: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .basalEnergyBurned,
            .restingHeartRate, .heartRateVariabilitySDNN, .bodyMass,
            .distanceWalkingRunning, .distanceCycling,
        ]
        for id in quantities { types.insert(HKQuantityType(id)) }
        return types
    }

    /// Ask HealthKit for read access. HealthKit never reveals whether *read*
    /// was granted (privacy), so we just try to fetch afterward.
    func requestAuthorization() async throws {
        guard Self.isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Build a sync payload from the last `daysBack` days of HealthKit data.
    func buildSyncRequest(daysBack: Int = 30) async throws -> HealthSyncRequest {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) ?? end
        let workouts = try await fetchWorkouts(start: start, end: end)
        let sleep = try await fetchSleep(start: start, end: end)
        let daily = try await fetchDaily(start: start, end: end)
        return HealthSyncRequest(workouts: workouts, sleep: sleep, daily: daily)
    }

    // MARK: - Workouts

    private func fetchWorkouts(start: Date, end: Date) async throws -> [WorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.map { w in
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())
                ?? w.statistics(for: HKQuantityType(.distanceCycling))?
                .sumQuantity()?.doubleValue(for: .meter())
            return WorkoutSample(
                id: w.uuid.uuidString,
                workoutType: Self.name(for: w.workoutActivityType),
                startAt: w.startDate,
                endAt: w.endDate,
                durationSeconds: w.duration,
                activeEnergyKcal: energy,
                distanceMeters: distance,
                source: w.sourceRevision.source.name
            )
        }
    }

    // MARK: - Sleep

    private struct SleepAcc { var inBed = 0.0, asleep = 0.0, rem = 0.0, deep = 0.0, core = 0.0, awake = 0.0 }

    private func fetchSleep(start: Date, end: Date) async throws -> [SleepNight] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 10_000
        )
        let samples = try await descriptor.result(for: store)

        var nights: [String: SleepAcc] = [:]
        for s in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            let day = Self.dayKey(s.endDate) // attribute the night to the wake day
            let dur = s.endDate.timeIntervalSince(s.startDate)
            var acc = nights[day] ?? SleepAcc()
            switch value {
            case .inBed: acc.inBed += dur
            case .awake: acc.awake += dur
            case .asleepREM: acc.rem += dur; acc.asleep += dur
            case .asleepDeep: acc.deep += dur; acc.asleep += dur
            case .asleepCore: acc.core += dur; acc.asleep += dur
            case .asleepUnspecified: acc.asleep += dur
            @unknown default: break
            }
            nights[day] = acc
        }

        return nights
            .filter { $0.value.asleep > 0 }
            .map { day, acc in
                SleepNight(
                    date: day,
                    inBedSeconds: acc.inBed > 0 ? acc.inBed : nil,
                    asleepSeconds: acc.asleep,
                    remSeconds: acc.rem > 0 ? acc.rem : nil,
                    deepSeconds: acc.deep > 0 ? acc.deep : nil,
                    coreSeconds: acc.core > 0 ? acc.core : nil,
                    awakeSeconds: acc.awake > 0 ? acc.awake : nil
                )
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Daily metrics

    private func fetchDaily(start: Date, end: Date) async throws -> [DailyMetric] {
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        let steps = try await dailyStat(.stepCount, unit: .count(), sum: true, start: start, end: end)
        let active = try await dailyStat(.activeEnergyBurned, unit: .kilocalorie(), sum: true, start: start, end: end)
        let basal = try await dailyStat(.basalEnergyBurned, unit: .kilocalorie(), sum: true, start: start, end: end)
        let restHR = try await dailyStat(.restingHeartRate, unit: hrUnit, sum: false, start: start, end: end)
        let hrv = try await dailyStat(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), sum: false, start: start, end: end)
        let mass = try await dailyStat(.bodyMass, unit: .gramUnit(with: .kilo), sum: false, start: start, end: end)

        let days = Set(steps.keys).union(active.keys).union(basal.keys)
            .union(restHR.keys).union(hrv.keys).union(mass.keys)

        return days.sorted(by: >).map { day in
            DailyMetric(
                date: day,
                steps: steps[day].map { Int($0) },
                activeEnergyKcal: active[day],
                restingEnergyKcal: basal[day],
                restingHeartRate: restHR[day],
                hrvMs: hrv[day],
                bodyMassKg: mass[day]
            )
        }
    }

    /// Daily bucketed statistic for a quantity type — cumulative sum or average.
    private func dailyStat(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit, sum: Bool, start: Date, end: Date
    ) async throws -> [String: Double] {
        let type = HKQuantityType(id)
        let anchor = Calendar.current.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: sum ? .cumulativeSum : .discreteAverage,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)

        var out: [String: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { stat, _ in
            let quantity = sum ? stat.sumQuantity() : stat.averageQuantity()
            if let value = quantity?.doubleValue(for: unit) {
                out[Self.dayKey(stat.startDate)] = value
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        case .swimming: return "swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .yoga: return "yoga"
        case .coreTraining: return "core"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        default: return "other"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
