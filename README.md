# Arete

Arete is a workout log for iPhone that tells you how recovered you are and what to train next.
It is made by The Rayze Company.

This repository holds the **recovery engine**: the maths behind Arete's per-muscle recovery and
whole-body Body Recovery scores. The rest of the app is closed source.

- [`RecoveryEngine/RecoveryEngine.swift`](RecoveryEngine/RecoveryEngine.swift): the engine, exactly
  as it ships in the app. It uses the app's own data types (`Workout`, `Exercise`, `MuscleGroup`,
  `AppSettings`…), which are not included, so it is here to read rather than to build.
- [`RecoveryEngine/RECOVERY-MODEL.md`](RecoveryEngine/RECOVERY-MODEL.md): how it works in plain
  terms, with the constants it reads from elsewhere in the app.
- [`CHANGELOG.md`](CHANGELOG.md): patch notes for every version.

## Links

- Support: https://rayzecompany.github.io/arete/
- Privacy Policy: https://rayzecompany.github.io/arete/privacy.html
- Terms of Use: https://rayzecompany.github.io/arete/terms.html
- Contact: rayzecompany@pm.me

Arete's scores are training guidance, not medical advice.
