import Foundation
import SwiftData

/// Each exercise's tracked muscles, resolved once per engine pass (resolving per logged
/// entry dominated the cost of drawing Home).
final class MuscleResolver {
    let active: Set<MuscleGroup>
    private let adductorsAsQuads = AppSettings.adductorsCountAsQuads
    private var cache: [PersistentIdentifier: MuscleSplit] = [:]

    init(active: Set<MuscleGroup> = Set(MuscleGroup.activeCases)) {
        self.active = active
    }

    func callAsFunction(_ exercise: Exercise) -> MuscleSplit {
        if let hit = cache[exercise.persistentModelID] { return hit }
        let split = exercise.trackedMuscles(active: active, adductorsAsQuads: adductorsAsQuads)
        cache[exercise.persistentModelID] = split
        return split
    }
}

/// How logged effort is read, fixed for one pass.
struct EffortMode {
    var enabled = AppSettings.effortEnabled
    var asRIR = AppSettings.effortAsRIR

    /// Out-of-range or unlogged effort falls back to the assumed RPE. RIR maps onto the
    /// RPE curve: 0 RIR ≈ 10, 1 ≈ 8, 2 ≈ 6.
    func effort(of set: ExerciseSet) -> Double {
        let logged = enabled ? set.effort(asRIR: asRIR) : nil
        guard let valid = logged.flatMap({ (0...10).contains($0) ? $0 : nil }) else {
            return RecoveryEngine.assumedRPE
        }
        return min(10, max(1, asRIR ? 10 - 2 * valid : valid))
    }
}

/// Muscle freshness (0–100) and whole-body fatigue from the workout log. All date maths is
/// in whole calendar days, so a reading doesn't drift through the day.
enum RecoveryEngine {
    static func daysBetween(_ from: Date, _ to: Date) -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return Double(calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    // MARK: Set fatigue

    static let maxFatiguePerSet: Double = 28.0
    /// Systemic curve: 10 → 28, 9 → 21.8, 8 → 17.0, 7 → 13.3.
    static let rpeFalloff: Double = 0.78
    /// Per-muscle curve, steeper: 10 → 28, 9 → 18.8, 8 → 12.6, 7 → 8.4.
    static let localRpeFalloff: Double = 0.67
    static let assumedRPE: Double = 7.5
    /// Assisting muscles take this share of a set's fatigue.
    static let secondaryFatigueShare: Double = 0.35

    /// Sets past the knee in one workout count sublinearly.
    static let systemicVolumeKnee: Double = 15.0
    static let localVolumeKnee: Double = 6.0
    static let volumeFalloffPower: Double = 0.45

    static func volumeDamping(sets: Int, knee: Double) -> Double {
        let n = Double(sets)
        guard n > knee else { return 1 }
        return pow(knee / n, volumeFalloffPower)
    }

    static func setFatigue(effort: Double, falloff: Double = rpeFalloff) -> Double {
        maxFatiguePerSet * pow(falloff, 10 - effort)
    }

    /// Duration curve with a >1 exponent, scaled by intensity around 5 (1 → 0.2×, 10 → 2×).
    static func cardioLoad(_ entry: CardioEntry) -> Double {
        guard let activity = entry.activity, entry.minutes > 0 else { return 0 }
        let intensity = (1...10).contains(entry.intensity) ? entry.intensity : 5
        return activity.fatiguePerHour * pow(entry.minutes / 60, 1.3) * (intensity / 5)
    }

    // MARK: Per-muscle freshness

    private static func legShare(_ muscle: MuscleGroup) -> Double {
        switch muscle {
        case .quads: return 1.0
        case .calves: return 0.9
        case .hamstrings: return 0.6
        case .adductors: return 0.4
        default: return 0
        }
    }

    /// Nothing recovers slower than this, so older workouts can't touch any muscle.
    private static let longestRecoveryDays: Double = MuscleGroup.allCases.map(\.recoveryDays).max() ?? 4

    /// Every tracked muscle's freshness in one pass. Fatigue decays linearly over each
    /// muscle's recovery window; cardio bleeds a little into the legs.
    static func allFreshness(workouts: [Workout], now: Date = Date(),
                             muscles resolve: MuscleResolver = MuscleResolver()) -> [MuscleGroup: Double] {
        let muscles = MuscleGroup.activeCases
        let multiplier = AppSettings.fatigueMultiplier
        let mode = EffortMode()
        var fatigue: [MuscleGroup: Double] = [:]

        for workout in workouts where !workout.isDisabled {
            let daysAgo = daysBetween(workout.date, now)
            guard daysAgo >= 0, daysAgo < longestRecoveryDays else { continue }

            let entries: [(primary: Set<MuscleGroup>, secondary: Set<MuscleGroup>, load: Double, sets: Int)] =
                workout.entries.compactMap { entry in
                    guard let exercise = entry.exercise else { return nil }
                    let filled = entry.filledWorkingSets
                    guard !filled.isEmpty else { return nil }
                    let split = resolve(exercise)
                    let load = filled.reduce(0) {
                        $0 + setFatigue(effort: mode.effort(of: $1), falloff: localRpeFalloff)
                    }
                    return (Set(split.primary), Set(split.secondary), load, filled.count)
                }
            let cardioLegLoad = workout.cardio.reduce(0.0) { total, entry in
                guard let activity = entry.activity else { return total }
                return total + cardioLoad(entry) * activity.legsShare
            }

            for muscle in muscles {
                guard daysAgo < muscle.recoveryDays else { continue }
                let remaining = 1.0 - (daysAgo / muscle.recoveryDays)
                var workoutFatigue = 0.0
                var contributingSets = 0
                for entry in entries {
                    let share: Double
                    if entry.primary.contains(muscle) {
                        share = 1.0
                    } else if entry.secondary.contains(muscle) {
                        share = secondaryFatigueShare
                    } else {
                        continue
                    }
                    workoutFatigue += entry.load * share
                    contributingSets += entry.sets
                }
                var total = workoutFatigue * volumeDamping(sets: contributingSets, knee: localVolumeKnee) * remaining
                let legs = legShare(muscle)
                if legs > 0 { total += cardioLegLoad * legs * remaining }
                // The personal dial applies after sets and cardio are combined.
                fatigue[muscle, default: 0] += total * multiplier
            }
        }

        var result: [MuscleGroup: Double] = [:]
        for muscle in muscles {
            result[muscle] = max(0, min(100, 100 - (fatigue[muscle] ?? 0)))
        }
        return result
    }

    /// Days since each muscle last did primary work in a filled set; never-trained muscles are absent.
    static func daysSinceTrained(workouts: [Workout], now: Date = Date(),
                                 muscles resolve: MuscleResolver = MuscleResolver()) -> [MuscleGroup: Double] {
        var latest: [MuscleGroup: Date] = [:]
        for workout in workouts where !workout.isDisabled {
            guard daysBetween(workout.date, now) >= 0 else { continue }
            for entry in workout.entries {
                guard let exercise = entry.exercise, !entry.filledWorkingSets.isEmpty else { continue }
                for muscle in resolve(exercise).primary where (latest[muscle] ?? .distantPast) < workout.date {
                    latest[muscle] = workout.date
                }
            }
        }
        return latest.mapValues { daysBetween($0, now) }
    }

    static func daysSinceTrained(_ muscle: MuscleGroup, workouts: [Workout], now: Date = Date()) -> Double? {
        daysSinceTrained(workouts: workouts, now: now)[muscle]
    }

    // MARK: Whole-body fatigue
    //
    // Acute + chronic, with LINEAR acute recovery. Exponential decay collapses training
    // blocks into train/rest/rest loops; a fixed daily recovery budget has a real
    // equilibrium (3–5 on / 1 off repeats indefinitely). The slow chronic term tightens
    // the cycle over weeks.

    static let acuteHorizon: Double = 35.0
    static let acuteRecoveryPerDay: Double = 26.0
    /// Raw load → points. 12 sets at the assumed effort ≈ 31 points the same day, 16 ≈ 40.
    static let acuteScale: Double = 0.17
    static let chronicHalfLife: Double = 12.0
    static let chronicHorizon: Double = 28.0
    static let chronicScale: Double = 0.004
    static let cardioSystemicWeight: Double = 3.1
    /// No single workout costs more than this raw load (~51 points).
    static let maxWorkoutSystemicLoad: Double = 300.0

    /// 0 = fully recovered … 100 = badly needs rest. `sleep` (the night ending on `now`'s
    /// morning) shifts this one reading only; it never enters the budget.
    static func totalFatigue(workouts: [Workout], now: Date = Date(), sleep: SleepEntry? = nil) -> Double {
        let active = workouts.filter { !$0.isDisabled }
        let mode = EffortMode()
        // Median tonnage of the 12 most recent workouts up to `now`: a unit-agnostic volume factor.
        let recentTonnages = active.filter { daysBetween($0.date, now) >= 0 }
            .sorted { $0.date > $1.date }
            .prefix(12).map(tonnage).filter { $0 > 0 }.sorted()
        let medianTonnage = recentTonnages[safe: recentTonnages.count / 2] ?? 0
        let multiplier = AppSettings.fatigueMultiplier

        var events: [(date: Date, points: Double)] = []
        var chronic: Double = 0
        for workout in active {
            let daysAgo = daysBetween(workout.date, now)
            guard daysAgo >= 0, daysAgo < acuteHorizon else { continue }

            var effort = liftEffort(workout, mode: mode)
            if medianTonnage > 0 {
                let t = tonnage(workout)
                if t > 0 { effort *= min(1.25, max(0.75, t / medianTonnage)) }
            }
            // The dial applies before the cap, so the cap still bounds one workout.
            effort = min(addingCardio(effort, from: workout) * multiplier, maxWorkoutSystemicLoad)

            if daysAgo < chronicHorizon {
                chronic += effort * pow(2, -daysAgo / chronicHalfLife)
            }
            events.append((workout.date, effort * acuteScale))
        }

        events.sort { $0.date < $1.date }
        var bucket: Double = 0
        var cursor: Date?
        for event in events {
            if let cursor {
                bucket = max(0, bucket - acuteRecoveryPerDay * daysBetween(cursor, event.date))
            }
            bucket += event.points
            cursor = event.date
        }
        if let cursor {
            bucket = max(0, bucket - acuteRecoveryPerDay * daysBetween(cursor, now))
        }

        let fatigue = min(100, bucket + chronic * chronicScale)
        guard let sleep else { return fatigue }
        return min(100, max(0, fatigue - SleepModel.effect(of: sleep)))
    }

    /// Raw load one workout dealt, without recency: drives the calendar's intensity colours.
    static func workoutLoad(_ workout: Workout) -> Double {
        addingCardio(liftEffort(workout), from: workout)
    }

    private static func addingCardio(_ effort: Double, from workout: Workout) -> Double {
        workout.cardio.reduce(effort) { $0 + cardioLoad($1) * cardioSystemicWeight }
    }

    static func liftEffort(_ workout: Workout, mode: EffortMode = EffortMode()) -> Double {
        let sets = workout.entries.flatMap(\.filledWorkingSets)
        return sets.reduce(0) { $0 + setFatigue(effort: mode.effort(of: $1)) }
            * volumeDamping(sets: sets.count, knee: systemicVolumeKnee)
    }

    /// weight × reps over filled working sets, drops included.
    static func tonnage(_ workout: Workout) -> Double {
        workout.entries.flatMap(\.filledWorkingSets).reduce(0) { $0 + $1.volume }
    }
}
