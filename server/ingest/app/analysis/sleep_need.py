"""
sleep_need.py — sleep need and debt estimation (APPROXIMATE).

sleep_need_min: how much sleep the body required, based on prior day's strain
and recovery. Formula mirrors WHOOP's published methodology:
  - baseline 450 min (7.5h)
  - +0–60 min scaled by prior strain (0–21)
  - −0–30 min scaled by prior recovery (0–100); high recovery = less need
"""
from __future__ import annotations

#: Baseline sleep need in minutes (population average).
_BASELINE_MIN = 450.0
#: Max additional need from high strain (strain=21 → +60 min).
_STRAIN_BONUS_MAX = 60.0
#: Max reduction from high recovery (recovery=100 → -30 min).
_RECOVERY_REDUCTION_MAX = 30.0


def compute_sleep_need(
    prior_strain: float | None,
    prior_recovery: float | None,
) -> float:
    """Return estimated sleep need in minutes for the coming night.

    Both inputs are from the PRIOR day. Returns the baseline when either
    is unavailable (cold-start safe).
    """
    need = _BASELINE_MIN
    if prior_strain is not None:
        need += (prior_strain / 21.0) * _STRAIN_BONUS_MAX
    if prior_recovery is not None:
        need -= (prior_recovery / 100.0) * _RECOVERY_REDUCTION_MAX
    return round(need, 1)


def compute_sleep_debt(sleep_need_min: float, total_sleep_min: float | None) -> float | None:
    """Return sleep debt in minutes (need − actual). Negative = surplus."""
    if total_sleep_min is None:
        return None
    return round(sleep_need_min - total_sleep_min, 1)