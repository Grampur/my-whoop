# OpenWhoop — Build Status

## Milestones

| Milestone | Status | Notes |
|-----------|--------|-------|
| M0 — Foundation, design system, tab scaffold, server API | ✅ Done | |
| M1 — Today tab (recovery ring, strain coach, sleep, HRV/RHR, live HR) | ✅ Done | Strain coach date-fallback fix applied to server main.py |
| M2 — Sleep tab (hypnogram, 7-night chart) | ✅ Done | |
| M3 — Trends tab | ✅ Done | |
| M4 — Device tab | ✅ Done | |
| M5 — Workouts tab (list, detail, tagging, offline delete queue) | ✅ Done | |
| M6 — Smart Alarm | ✅ Done | Firmware alarm works. Smart-wake high-freq-sync path intentionally disabled (breaks data pipeline). Fixed-time firmware alarm is the real path. |
| M7 — Notifications + Polish | ✅ Done | Recovery notifier, sync-stale nudge, bedtime nudge, battery alerts all wired |

## Known Gaps / Future Work

- **Sleep staging accuracy** — current staging uses gravity threshold (still/active), not real wake/light/deep/REM
- **Metrics accuracy overhaul** — SpO2 and skin temp are raw ADC / approximate; HRV, strain, recovery not validated against WHOOP ground truth
- **Smart-wake** — scoped out due to high-freq-sync data pipeline conflict; fixed-time alarm is the fallback
