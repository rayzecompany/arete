# How Arete's recovery engine works

Two readings come out of the engine:

- **Muscle recovery**: 0–100 per muscle, where 100 is fully fresh.
- **Body Recovery**: whole-body fatigue, 0 (fully recovered) to 100 (badly needs rest). The app
  shows it flipped, as a percentage recovered.

All date maths uses whole calendar days, so a reading doesn't drift through the day.

## 1. What one set costs

A working set's fatigue depends on its effort (RPE 1–10):

    fatigue = 28 × falloff^(10 − RPE)

- Whole-body falloff is **0.78**: RPE 10 → 28, 9 → 21.8, 8 → 17.0, 7 → 13.3.
- Per-muscle falloff is steeper, **0.67**: RPE 10 → 28, 9 → 18.8, 8 → 12.6, 7 → 8.4.
- A set with no effort logged counts as **RPE 7.5**. RIR is converted to RPE (0 RIR ≈ 10, 1 ≈ 8,
  2 ≈ 6).
- Warm-ups don't count. A drop set's extra drops add to tonnage (below) but not to the set count.

**Volume damping.** Sets past a "knee" in one workout count for less:
`× (knee ÷ sets)^0.45` once sets exceed the knee. The knee is **6 sets** per muscle and
**15 sets** for the whole workout.

## 2. Muscle recovery

For each muscle, every recent workout adds fatigue:

- Muscles an exercise mainly works take the full set cost; muscles that assist take **35%**.
- That fatigue fades in a straight line to zero over the muscle's recovery window:

| Recovery window | Muscles |
|---|---|
| 3.8 days | Quads, hamstrings, glutes, back (lats, mid back), adductors |
| 2.9 days | Chest (upper chest), traps |
| 1.9 days | Shoulders (front, middle and rear delts), biceps, triceps |
| 1.45 days | Forearms, calves, abs, neck |

- Cardio adds a little fatigue to the legs: quads 100%, calves 90%, hamstrings 60% and
  adductors 40% of the activity's leg share (table below).
- Recovery = 100 − total fatigue, kept between 0 and 100.

## 3. Body Recovery (whole-body fatigue)

Two parts, added together and capped at 100:

**Acute.** Each workout in the last 35 days adds points (`raw load × 0.17`) to a bucket, and the
bucket drains by a fixed **26 points a day**, never below zero. A steady drain, rather than
exponential decay, lets a routine like 3–5 days on, 1 off settle into a stable rhythm instead of
collapsing into train/rest/rest. Roughly, 12 sets at RPE 7.5 add ~31 points the same day, 16
sets ~40.

**Chronic.** Workouts in the last 28 days also build a slow term that halves every **12 days**
(`× 0.004`). It tightens the cycle when hard weeks stack up.

A workout's raw load is:

- its sets' whole-body cost with volume damping (above),
- × **0.75–1.25** by its tonnage (weight × reps) against the median of your last 12 workouts, so
  a heavier-than-usual session counts for more,
- \+ cardio load × **3.1**,
- capped at **300** (≈51 points), so no single workout can wipe you out.

**Cardio load** = fatigue per hour × hours^1.3 × (intensity ÷ 5):

| Activity | Fatigue per hour | Leg share |
|---|---|---|
| Treadmill | 10 | 0.18 |
| Incline treadmill | 16 | 0.30 |
| Biking | 12 | 0.25 |
| Elliptical | 11 | 0.22 |
| Outdoor walking | 6 | 0.10 |
| Soccer | 24 | 0.30 |
| Basketball | 20 | 0.28 |
| Swimming | 16 | 0.08 |
| Pickleball | 17 | 0.26 |

## 4. Your settings

- **Fatigue Sensitivity** multiplies every workout's cost (set and cardio load) before the
  300 cap.
- **Sleep** (optional): the night before can nudge today's Body Recovery up or down a few
  points. It changes that one reading only and never enters the running totals.
