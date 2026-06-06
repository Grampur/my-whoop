# OpenWhoop — Build Status

Last updated: 2026-06-06

## Milestones

| Milestone | Status | Notes |
|-----------|--------|-------|
| M0 — Foundation, design system, tab scaffold, server API client, settings | ✅ Done | |
| M1 — Today tab (recovery ring, strain coach, sleep, HRV/RHR, live HR) | ✅ Done | Strain coach date-fallback bug fixed in server `main.py` — queries last 2 days for recovery if today's row has none yet |
| M2 — Sleep tab (hypnogram, 7-night chart) | ✅ Done | |
| M3 — Trends tab | ✅ Done | |
| M4 — Device tab | ✅ Done | |
| M5 — Workouts tab (list, detail, tagging, offline delete queue) | ✅ Done | |
| M6 — Smart Alarm | ✅ Done | Firmware alarm (cmd 66) works and tested on-device. Smart-wake high-freq-sync path intentionally disabled — entering high-freq-sync breaks the data pipeline on this firmware. Fixed-time firmware alarm is the real path. |
| M7 — Notifications + Polish | ✅ Done | Recovery notifier, sync-stale nudge, bedtime nudge, battery alerts all implemented and wired |

## Known Gaps / Future Work

### SpO2 and Skin Temp Calibration (blocked)
The ratio-of-ratios SpO2 formula and linear skin temp conversion are implemented correctly but use uncalibrated default constants (TI SLAA655 textbook values). The fitting infrastructure (`fit_spo2()`, `fit_skin_temp()` in `server/ingest/app/analysis/units.py`) is written and waiting. **Blocked on ground truth data** — requires an overlap period where the same raw ADC data was also scored by WHOOP's cloud. WHOOP membership lapsed in 2023; no raw data overlap exists. Cannot be unblocked without either re-subscribing to WHOOP or using the developer API to pull 2023 historical data for a sanity check (not true calibration).

### Sleep Staging
Current staging uses a multi-signal pipeline: Cole-Kripke sleep/wake detection from accelerometer + cardiorespiratory features (HR, RMSSD, HF power, HR variability, respiratory rate variability) per 30-second epoch + a hand-written rule classifier + post-processing smoothing and physiology re-imposition. The classifier seam in `sleep_features.classify_epochs()` is explicitly designed as a swap point for a trained model (sleepecg GRU). A `sleep-staging-v2` branch exists but was not pursued after reviewing the code — the current implementation is already substantially more sophisticated than a simple gravity threshold. Improvement would require PSG ground truth to validate, which is not available.

### Metrics Accuracy Overhaul (partially complete)
- **HRV** — Solid. Task Force RMSSD, Kubios artifact correction via neurokit2, segment-aware pooling, sleep-window selection. No known gaps.
- **Resting HR** — Solid. Nightly lowest 5-min rolling mean.
- **Strain** — Edwards zone TRIMP → log 0–21 scale. Physiologically reasonable, not validated against WHOOP ground truth.
- **Recovery** — Baseline-normalized weighted composite (HRV, RHR, sleep performance, respiratory). Physiologically reasonable, not validated against WHOOP ground truth.
- **SpO2** — Uncalibrated. See above.
- **Skin temp** — Uncalibrated. See above.
- **Respiratory rate** — Welch spectral estimator, approximate.

## Branch Notes
- `main` — production, deployed via Docker
- `sleep-staging-v2` — created 2026-06-06, not yet used; reserved for future sleepecg integration if ground truth becomes available