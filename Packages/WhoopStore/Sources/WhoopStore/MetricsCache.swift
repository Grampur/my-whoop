import Foundation
import GRDB

// MARK: - Offline cache of SERVER-computed metrics (Task 3.1 → M0.4)
// This file is purely a local cache of values computed by the server — the phone does NO metric
// computation here. DailyMetric and CachedSleepSession mirror the server's daily_metrics /
// sleep_sessions tables and are cached locally so History = union(phone-collected raw streams,
// server-computed derived metrics). ServerSync.pull() populates this cache; MetricsRepository
// reads it for the view layer.

/// One cached sleep session pulled from the server's /v1/sleep. Natural key (deviceId, startTs).
/// `stagesJSON` is the verbatim JSON array of stage segments ([{start,end,stage}]) — stored as a
/// string so the cache stays schema-agnostic about the staging shape.
public struct CachedSleepSession: Equatable, Codable {
    public let startTs: Int          // unix seconds
    public let endTs: Int            // unix seconds
    public let efficiency: Double?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let stagesJSON: String?
    public init(startTs: Int, endTs: Int, efficiency: Double?, restingHr: Int?,
                avgHrv: Double?, stagesJSON: String?) {
        self.startTs = startTs; self.endTs = endTs
        self.efficiency = efficiency; self.restingHr = restingHr
        self.avgHrv = avgHrv; self.stagesJSON = stagesJSON
    }
}

/// One cached daily-metrics row pulled from the server's /v1/daily. Natural key (deviceId, day).
public struct DailyMetric: Equatable, Codable {
    public let day: String           // YYYY-MM-DD
    public let totalSleepMin: Double?
    public let efficiency: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let lightMin: Double?
    public let disturbances: Int?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let recovery: Double?
    public let strain: Double?
    public let exerciseCount: Int?
    // In-sleep signal aggregates (v7 columns). All nullable; computed server-side.
    public let spo2Pct: Double?        // mean SpO2 (%) during sleep
    public let skinTempDevC: Double?   // skin-temperature deviation (°C) from baseline
    public let respRateBpm: Double?    // mean respiration rate (breaths/min) during sleep
    public let sleepNeedMin: Double?
    public let sleepDebtMin: Double?
    public init(day: String, totalSleepMin: Double?, efficiency: Double?, deepMin: Double?,
                remMin: Double?, lightMin: Double?, disturbances: Int?, restingHr: Int?,
                avgHrv: Double?, recovery: Double?, strain: Double?, exerciseCount: Int?,
                spo2Pct: Double? = nil, skinTempDevC: Double? = nil, respRateBpm: Double? = nil,
                sleepNeedMin: Double? = nil, sleepDebtMin: Double? = nil) {
        self.day = day; self.totalSleepMin = totalSleepMin; self.efficiency = efficiency
        self.deepMin = deepMin; self.remMin = remMin; self.lightMin = lightMin
        self.disturbances = disturbances; self.restingHr = restingHr; self.avgHrv = avgHrv
        self.recovery = recovery; self.strain = strain; self.exerciseCount = exerciseCount
        self.spo2Pct = spo2Pct; self.skinTempDevC = skinTempDevC; self.respRateBpm = respRateBpm
        self.sleepNeedMin = sleepNeedMin; self.sleepDebtMin = sleepDebtMin
    }
}

public struct CachedWorkout: Equatable {
    public let startTs: Int
    public let endTs: Int
    public let avgHr: Double
    public let peakHr: Int
    public let strain: Double?
    public let kind: String?
    public let durationS: Int
    public let zoneTimePctJSON: String?   // [Int:Double] serialized as JSON text
    public let avgHrrPct: Double?
    public let hrmax: Double?
    public let hrmaxSource: String
    public let caloriesKcal: Double?
    public let caloriesKj: Double?

    public init(startTs: Int, endTs: Int, avgHr: Double, peakHr: Int, strain: Double?,
                kind: String?, durationS: Int, zoneTimePctJSON: String?,
                avgHrrPct: Double?, hrmax: Double?, hrmaxSource: String,
                caloriesKcal: Double?, caloriesKj: Double?) {
        self.startTs = startTs; self.endTs = endTs
        self.avgHr = avgHr; self.peakHr = peakHr
        self.strain = strain; self.kind = kind; self.durationS = durationS
        self.zoneTimePctJSON = zoneTimePctJSON
        self.avgHrrPct = avgHrrPct; self.hrmax = hrmax; self.hrmaxSource = hrmaxSource
        self.caloriesKcal = caloriesKcal; self.caloriesKj = caloriesKj
    }
}

extension WhoopStore {
    // MARK: - Upserts (idempotent by natural key; latest server value wins on conflict)

    /// Upsert cached sleep sessions. Natural key (deviceId, startTs). Returns rows changed.
    @discardableResult
    public func upsertSleepSessions(_ sessions: [CachedSleepSession], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var n = 0
            for s in sessions {
                try db.execute(sql: """
                    INSERT INTO sleepSession
                        (deviceId, startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, startTs) DO UPDATE SET
                        endTs = excluded.endTs,
                        efficiency = excluded.efficiency,
                        restingHr = excluded.restingHr,
                        avgHrv = excluded.avgHrv,
                        stagesJSON = excluded.stagesJSON
                    """, arguments: [deviceId, s.startTs, s.endTs, s.efficiency,
                                     s.restingHr, s.avgHrv, s.stagesJSON])
                n += db.changesCount
            }
            return n
        }
    }

    /// Upsert cached daily metrics. Natural key (deviceId, day). Returns rows changed.
    @discardableResult
    public func upsertDailyMetrics(_ days: [DailyMetric], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var n = 0
            for d in days {
                try db.execute(sql: """
                    INSERT INTO dailyMetric
                        (deviceId, day, totalSleepMin, efficiency, deepMin, remMin, lightMin,
                         disturbances, restingHr, avgHrv, recovery, strain, exerciseCount,
                         spo2Pct, skinTempDevC, respRateBpm, sleepNeedMin, sleepDebtMin)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, day) DO UPDATE SET
                        totalSleepMin = excluded.totalSleepMin,
                        efficiency = excluded.efficiency,
                        deepMin = excluded.deepMin,
                        remMin = excluded.remMin,
                        lightMin = excluded.lightMin,
                        disturbances = excluded.disturbances,
                        restingHr = excluded.restingHr,
                        avgHrv = excluded.avgHrv,
                        recovery = excluded.recovery,
                        strain = excluded.strain,
                        exerciseCount = excluded.exerciseCount,
                        spo2Pct = excluded.spo2Pct,
                        skinTempDevC = excluded.skinTempDevC,
                        respRateBpm = excluded.respRateBpm,
                        sleepNeedMin = excluded.sleepNeedMin,
                        sleepDebtMin = excluded.sleepDebtMin
                    """, arguments: [deviceId, d.day, d.totalSleepMin, d.efficiency, d.deepMin,
                                     d.remMin, d.lightMin, d.disturbances, d.restingHr, d.avgHrv,
                                     d.recovery, d.strain, d.exerciseCount,
                                     d.spo2Pct, d.skinTempDevC, d.respRateBpm, d.sleepNeedMin, d.sleepDebtMin])
                n += db.changesCount
            }
            return n
        }
    }

    /// Upsert cached workout bouts. Natural key (deviceId, startTs). Returns rows changed.
    @discardableResult
    public func upsertWorkouts(_ workouts: [CachedWorkout], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var n = 0
            for w in workouts {
                try db.execute(sql: """
                    INSERT INTO workoutSession
                        (deviceId, startTs, endTs, avgHr, peakHr, strain, kind, durationS,
                         zoneTimePctJSON, avgHrrPct, hrmax, hrmaxSource, caloriesKcal, caloriesKj)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, startTs) DO UPDATE SET
                        endTs = excluded.endTs,
                        avgHr = excluded.avgHr,
                        peakHr = excluded.peakHr,
                        strain = excluded.strain,
                        kind = excluded.kind,
                        durationS = excluded.durationS,
                        zoneTimePctJSON = excluded.zoneTimePctJSON,
                        avgHrrPct = excluded.avgHrrPct,
                        hrmax = excluded.hrmax,
                        hrmaxSource = excluded.hrmaxSource,
                        caloriesKcal = excluded.caloriesKcal,
                        caloriesKj = excluded.caloriesKj
                    """, arguments: [deviceId, w.startTs, w.endTs, w.avgHr, w.peakHr,
                                     w.strain, w.kind, w.durationS, w.zoneTimePctJSON,
                                     w.avgHrrPct, w.hrmax, w.hrmaxSource,
                                     w.caloriesKcal, w.caloriesKj])
                n += db.changesCount
            }
            return n
        }
    }

    // MARK: - Reads

    /// Cached sleep sessions overlapping [from, to] (by startTs), oldest first.
    public func sleepSessions(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [CachedSleepSession] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON FROM sleepSession
                WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
                ORDER BY startTs ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map {
                    CachedSleepSession(startTs: $0["startTs"], endTs: $0["endTs"],
                                       efficiency: $0["efficiency"], restingHr: $0["restingHr"],
                                       avgHrv: $0["avgHrv"], stagesJSON: $0["stagesJSON"])
                }
        }
    }

    /// Cached daily metrics for days in [from, to] (lexicographic YYYY-MM-DD compare), oldest first.
    public func dailyMetrics(deviceId: String, from: String, to: String) async throws -> [DailyMetric] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, totalSleepMin, efficiency, deepMin, remMin, lightMin, disturbances,
                       restingHr, avgHrv, recovery, strain, exerciseCount,
                       spo2Pct, skinTempDevC, respRateBpm, sleepNeedMin, sleepDebtMin FROM dailyMetric
                WHERE deviceId = ? AND day >= ? AND day <= ?
                ORDER BY day ASC
                """, arguments: [deviceId, from, to])
                .map {
                    DailyMetric(day: $0["day"], totalSleepMin: $0["totalSleepMin"],
                                efficiency: $0["efficiency"], deepMin: $0["deepMin"],
                                remMin: $0["remMin"], lightMin: $0["lightMin"],
                                disturbances: $0["disturbances"], restingHr: $0["restingHr"],
                                avgHrv: $0["avgHrv"], recovery: $0["recovery"],
                                strain: $0["strain"], exerciseCount: $0["exerciseCount"],
                                spo2Pct: $0["spo2Pct"], skinTempDevC: $0["skinTempDevC"],
                                respRateBpm: $0["respRateBpm"],
                                sleepNeedMin: $0["sleepNeedMin"], sleepDebtMin: $0["sleepDebtMin"])
                }
        }
    }

    /// Delete all cached workout bouts for [fromTs, toTs] (epoch seconds, by startTs).
    /// Used before upserting a fresh server response so stale rows from a server recompute
    /// don't persist alongside the new set.
    @discardableResult
    public func deleteWorkouts(deviceId: String, from fromTs: Int, to toTs: Int) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                DELETE FROM workoutSession
                WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
                """, arguments: [deviceId, fromTs, toTs])
            return db.changesCount
        }
    }

    /// Cached workout bouts for [fromTs, toTs] (epoch seconds, by startTs), newest first.
    public func workouts(deviceId: String, from fromTs: Int, to toTs: Int) async throws -> [CachedWorkout] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT startTs, endTs, avgHr, peakHr, strain, kind, durationS,
                       zoneTimePctJSON, avgHrrPct, hrmax, hrmaxSource, caloriesKcal, caloriesKj
                FROM workoutSession
                WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
                ORDER BY startTs DESC
                """, arguments: [deviceId, fromTs, toTs])
                .map {
                    CachedWorkout(startTs: $0["startTs"], endTs: $0["endTs"],
                                  avgHr: $0["avgHr"], peakHr: $0["peakHr"],
                                  strain: $0["strain"], kind: $0["kind"],
                                  durationS: $0["durationS"],
                                  zoneTimePctJSON: $0["zoneTimePctJSON"],
                                  avgHrrPct: $0["avgHrrPct"], hrmax: $0["hrmax"],
                                  hrmaxSource: $0["hrmaxSource"] ?? "",
                                  caloriesKcal: $0["caloriesKcal"],
                                  caloriesKj: $0["caloriesKj"])
                }
        }
    }
}