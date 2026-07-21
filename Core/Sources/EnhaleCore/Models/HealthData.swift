import Foundation

/// Health payloads mirroring the backend `/health` contract. The iOS app fills
/// these from HealthKit; a future Android app would fill them from Health
/// Connect. Date-only fields (`day`) are ISO `yyyy-MM-dd` strings — the backend
/// stores them as calendar dates, and keeping them as strings avoids
/// datetime-decoding ambiguity on the client.

public struct WorkoutSample: Codable, Identifiable, Sendable, Equatable {
    public var id: String            // HealthKit sample UUID (idempotency key)
    public var workoutType: String
    public var startAt: Date
    public var endAt: Date
    public var durationSeconds: Double
    public var activeEnergyKcal: Double?
    public var distanceMeters: Double?
    public var source: String?

    public init(id: String, workoutType: String, startAt: Date, endAt: Date,
                durationSeconds: Double, activeEnergyKcal: Double? = nil,
                distanceMeters: Double? = nil, source: String? = nil) {
        self.id = id; self.workoutType = workoutType
        self.startAt = startAt; self.endAt = endAt
        self.durationSeconds = durationSeconds
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceMeters = distanceMeters; self.source = source
    }
}

public struct SleepNight: Codable, Identifiable, Sendable, Equatable {
    public var date: String          // yyyy-MM-dd (the wake day)
    public var inBedSeconds: Double?
    public var asleepSeconds: Double
    public var remSeconds: Double?
    public var deepSeconds: Double?
    public var coreSeconds: Double?
    public var awakeSeconds: Double?

    public var id: String { date }

    public init(date: String, inBedSeconds: Double? = nil, asleepSeconds: Double,
                remSeconds: Double? = nil, deepSeconds: Double? = nil,
                coreSeconds: Double? = nil, awakeSeconds: Double? = nil) {
        self.date = date; self.inBedSeconds = inBedSeconds
        self.asleepSeconds = asleepSeconds; self.remSeconds = remSeconds
        self.deepSeconds = deepSeconds; self.coreSeconds = coreSeconds
        self.awakeSeconds = awakeSeconds
    }
}

public struct DailyMetric: Codable, Identifiable, Sendable, Equatable {
    public var date: String          // yyyy-MM-dd
    public var steps: Int?
    public var activeEnergyKcal: Double?
    public var restingEnergyKcal: Double?
    public var restingHeartRate: Double?
    public var hrvMs: Double?
    public var bodyMassKg: Double?

    public var id: String { date }

    public init(date: String, steps: Int? = nil, activeEnergyKcal: Double? = nil,
                restingEnergyKcal: Double? = nil, restingHeartRate: Double? = nil,
                hrvMs: Double? = nil, bodyMassKg: Double? = nil) {
        self.date = date; self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.restingHeartRate = restingHeartRate
        self.hrvMs = hrvMs; self.bodyMassKg = bodyMassKg
    }
}

public struct HealthSyncRequest: Codable, Sendable {
    public var workouts: [WorkoutSample]
    public var sleep: [SleepNight]
    public var daily: [DailyMetric]

    public init(workouts: [WorkoutSample] = [], sleep: [SleepNight] = [], daily: [DailyMetric] = []) {
        self.workouts = workouts; self.sleep = sleep; self.daily = daily
    }
}

public struct HealthSyncResult: Codable, Sendable {
    public var workoutsUpserted: Int
    public var sleepUpserted: Int
    public var dailyUpserted: Int
}

public struct HealthSummary: Codable, Sendable {
    public var workouts: [WorkoutSample]
    public var sleep: [SleepNight]
    public var daily: [DailyMetric]
}
