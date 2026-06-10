"""FastAPI ingest service. Bearer-auth write endpoint + health check + read API +
the static datastore dashboard."""
import datetime as _dt
import logging
import os
import threading
import time

import psycopg
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import db, ingest, read, store
from .analysis import daily
from .config import load_config

_log = logging.getLogger("whoop.ingest")

cfg = load_config()
db.bootstrap_schema(cfg.db_dsn)

# Docs/schema disabled: don't advertise the API surface publicly (every /v1 route is
# Bearer-gated, but the OpenAPI schema + Swagger UI were world-readable).
app = FastAPI(title="Whoop Ingest", docs_url=None, redoc_url=None, openapi_url=None)

_STATIC = os.path.join(os.path.dirname(__file__), "static")
app.mount("/static", StaticFiles(directory=_STATIC), name="static")

# --- Auto-recompute throttle -------------------------------------------------
# The phone uploads opportunistically (every ~30s while connected, plus backlog
# drains), so /v1/ingest-decoded can fire many times per minute — each touching
# the SAME current day. compute_day now runs the heavy neurokit sleep-staging
# pipeline, so recomputing a day on every upload saturates CPU/memory. We
# therefore (a) single-flight recomputes (never run two at once) and (b) debounce
# per (device, day) so a day recomputes at most once per cooldown. On-demand
# freshness is always available via POST /v1/compute-daily.
_RECOMPUTE_COOLDOWN_S = 120.0
_recompute_lock = threading.Lock()
_last_recompute: dict[tuple[str, _dt.date], float] = {}


@app.get("/")
def dashboard():
    """Serve the datastore dashboard (static SPA reading the /v1 read API)."""
    return FileResponse(os.path.join(_STATIC, "index.html"))


@app.get("/architecture")
def architecture():
    """Serve the device-link architecture page (how we talk to the strap, no byte detail)."""
    return FileResponse(os.path.join(_STATIC, "architecture.html"))


def require_auth(authorization: str = Header(default="")) -> None:
    expected = f"Bearer {cfg.api_key}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="unauthorized")


class Frame(BaseModel):
    seq: int | None = None
    hex: str


class ClockRef(BaseModel):
    device: int
    wall: int


class Device(BaseModel):
    device_id: str
    mac: str | None = None
    name: str | None = None


class IngestBatch(BaseModel):
    batch_id: str
    device: Device
    clock_ref: ClockRef
    frames: list[Frame]
    decode_streams: bool = True


# ── Decoded-upload models ────────────────────────────────────────────────────

class DecodedDevice(BaseModel):
    id: str
    mac: str | None = None
    name: str | None = None


class DecodedStreams(BaseModel):
    hr: list[dict] = []
    rr: list[dict] = []
    events: list[dict] = []
    battery: list[dict] = []
    # Type-47 V24 biometric history (optional; older clients omit these). Values are
    # raw ADC for spo2/skin_temp/resp; gravity is the accel-derived vector in g.
    spo2: list[dict] = []
    skin_temp: list[dict] = []
    resp: list[dict] = []
    gravity: list[dict] = []


class DecodedBatch(BaseModel):
    device: DecodedDevice
    streams: DecodedStreams


@app.get("/healthz")
def healthz():
    try:
        with psycopg.connect(cfg.db_dsn, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"db unavailable: {e}")


@app.post("/v1/ingest", dependencies=[Depends(require_auth)])
def ingest_batch(batch: IngestBatch):
    payload = batch.model_dump()
    with psycopg.connect(cfg.db_dsn) as conn:
        result = ingest.process_batch(conn, cfg, payload)
        conn.commit()
    return result


def _batch_dates_utc(streams: dict) -> set[_dt.date]:
    """UTC calendar dates spanned by every stream-row ts in an ingest batch."""
    days: set[_dt.date] = set()
    for rows in streams.values():
        for r in rows or []:
            ts = r.get("ts")
            if ts is None:
                continue
            days.add(_dt.datetime.fromtimestamp(float(ts), _dt.timezone.utc).date())
    return days


@app.post("/v1/ingest-decoded", dependencies=[Depends(require_auth)])
def ingest_decoded(batch: DecodedBatch):
    payload = batch.model_dump()
    device_id = payload["device"]["id"]
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, device_id,
                            mac=payload["device"].get("mac"),
                            name=payload["device"].get("name"))
        counts = store.upsert_streams(conn, device_id, payload["streams"])
        conn.commit()
        # Recompute the day(s) this batch touched — throttled (see _RECOMPUTE_*).
        # Best-effort: a compute error must NOT fail the ingest (the raw streams
        # are already persisted) — log + move on.
        for day in _batch_dates_utc(payload["streams"]):
            key = (device_id, day)
            if time.monotonic() - _last_recompute.get(key, 0.0) < _RECOMPUTE_COOLDOWN_S:
                continue  # debounce: this day was recomputed very recently
            if not _recompute_lock.acquire(blocking=False):
                continue  # single-flight: a recompute is already running; a later upload catches up
            try:
                daily.compute_day(conn, device_id, day)
                conn.commit()
            except Exception:
                conn.rollback()
                _log.exception("compute_day failed for %s %s (ingest still 200)", device_id, day)
            finally:
                _last_recompute[key] = time.monotonic()  # throttle successes AND failures
                _recompute_lock.release()
    return {"upserted": counts}


@app.get("/v1/devices", dependencies=[Depends(require_auth)])
def get_devices():
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.list_devices(conn)


@app.get("/v1/batches", dependencies=[Depends(require_auth)])
def get_batches(device: str, limit: int = 100):
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.list_batches(conn, device_id=device, limit=limit)


@app.get("/v1/summary", dependencies=[Depends(require_auth)])
def get_summary(device: str,
                from_: int = Query(0, alias="from"),
                to: int = Query(2_000_000_000, alias="to")):
    """Exact (unlimited) counts per decoded stream + raw batches, for accurate dashboard totals."""
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.counts(conn, device_id=device, start=from_, end=to)


@app.get("/v1/streams/{kind}", dependencies=[Depends(require_auth)])
def get_stream(kind: str, device: str,
               from_: int = Query(0, alias="from"),
               to: int = Query(2_000_000_000, alias="to"),
               limit: int = 5000,
               max_points: int | None = None):
    try:
        with psycopg.connect(cfg.db_dsn) as conn:
            return read.query_stream(conn, kind, device_id=device, start=from_, end=to,
                                     limit=limit, max_points=max_points)
    except ValueError:
        raise HTTPException(status_code=404, detail=f"unknown stream kind: {kind}")


# ── Daily analysis endpoints (Task 2.5) ──────────────────────────────────────

class ComputeDaily(BaseModel):
    device: str
    date: str  # YYYY-MM-DD


def _parse_date(s: str) -> _dt.date:
    try:
        return _dt.date.fromisoformat(s)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"invalid date (want YYYY-MM-DD): {s!r}")


@app.post("/v1/compute-daily", dependencies=[Depends(require_auth)])
def compute_daily(body: ComputeDaily):
    """Compute + persist the daily metrics for a device/date, returning the summary."""
    day = _parse_date(body.date)
    with psycopg.connect(cfg.db_dsn) as conn:
        result = daily.compute_day(conn, body.device, day)
        conn.commit()
    return result


@app.get("/v1/daily", dependencies=[Depends(require_auth)])
def get_daily(device: str,
              from_: str = Query(..., alias="from"),
              to: str = Query(..., alias="to")):
    """daily_metrics rows over the inclusive [from, to] date range (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_daily(conn, device, start, end)


@app.get("/v1/sleep", dependencies=[Depends(require_auth)])
def get_sleep(device: str, date: str):
    """Sleep sessions whose night ENDS on ``date`` (YYYY-MM-DD)."""
    day = _parse_date(date)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_sleep(conn, device, day)


# ── Profile endpoints ─────────────────────────────────────────────────────────

_VALID_SEX = {"male", "female", "nonbinary"}


class ProfileBody(BaseModel):
    device: str
    height_cm: float | None = None
    weight_kg: float | None = None
    age: int | None = None
    sex: str | None = None


@app.get("/v1/profile", dependencies=[Depends(require_auth)])
def get_profile(device: str):
    """Return the stored profile for a device, or {} if none exists."""
    with psycopg.connect(cfg.db_dsn) as conn:
        row = read.query_profile(conn, device)
    return row or {}


@app.post("/v1/profile", dependencies=[Depends(require_auth)])
def upsert_profile(body: ProfileBody):
    """Create or update the user profile (height/weight/age/sex) for a device."""
    sex = body.sex
    if sex is not None:
        sex = sex.lower().strip()
        if sex not in _VALID_SEX:
            raise HTTPException(
                status_code=422,
                detail=f"sex must be one of {sorted(_VALID_SEX)} or null; got {body.sex!r}",
            )
    with psycopg.connect(cfg.db_dsn) as conn:
        store.ensure_device(conn, body.device)
        store.upsert_profile(conn, body.device,
                             height_cm=body.height_cm,
                             weight_kg=body.weight_kg,
                             age=body.age,
                             sex=sex)
        conn.commit()
        row = read.query_profile(conn, body.device)
    return row


# ── Workouts endpoint ─────────────────────────────────────────────────────────

@app.get("/v1/workouts", dependencies=[Depends(require_auth)])
def get_workouts(device: str,
                 from_: str = Query(..., alias="from"),
                 to: str = Query(..., alias="to")):
    """Exercise sessions whose start_ts (UTC date) is in [from, to] (YYYY-MM-DD)."""
    start, end = _parse_date(from_), _parse_date(to)
    with psycopg.connect(cfg.db_dsn) as conn:
        return read.query_workouts(conn, device, start, end)

# --- Workout tagging -----------------------------------------------------------
@app.patch("/v1/workouts/{start_ts}/kind", dependencies=[Depends(require_auth)])
def patch_workout_kind(start_ts: float, device: str, body: dict):
    """Manually tag a workout's activity kind (e.g. 'golf', 'weightlifting')."""
    kind = body.get("kind")  # None = clear the tag
    with psycopg.connect(cfg.db_dsn) as conn:
        result = conn.execute(
            "UPDATE exercise_sessions SET kind = %s "
            "WHERE device_id = %s AND ABS(EXTRACT(EPOCH FROM start_ts) - %s) < 2 "
            "RETURNING start_ts",
            (kind, device, start_ts)
        )
        row = result.fetchone()
        conn.commit()
    if row is None:
        raise HTTPException(status_code=404, detail="workout not found")
    return {"status": "ok", "kind": kind}

# --- Delete Workout ------------------------------------------------------------
@app.delete("/v1/workouts/{start_ts}", dependencies=[Depends(require_auth)])
def delete_workout(start_ts: float, device: str):
    """Delete a workout bout by start_ts. Returns 200 if deleted, 404 if not found."""
    with psycopg.connect(cfg.db_dsn) as conn:
        result = conn.execute(
            "DELETE FROM exercise_sessions "
            "WHERE device_id = %s AND ABS(EXTRACT(EPOCH FROM start_ts) - %s) < 2 "
            "RETURNING start_ts",
            (device, start_ts)
        )
        row = result.fetchone()
        conn.commit()
    if row is None:
        raise HTTPException(status_code=404, detail="workout not found")
    return {"status": "deleted"}

# ── Manual workout entry ───────────────────────────────────────────────────────

class ManualWorkout(BaseModel):
    device: str
    start_ts: float   # unix epoch seconds
    end_ts: float     # unix epoch seconds
    kind: str | None = None  # e.g. "weightlifting", "cardio"

@app.post("/v1/manual-workout", dependencies=[Depends(require_auth)])
def manual_workout(body: ManualWorkout):
    """Log a workout retroactively by time window. Pulls HR + gravity from DB,
    runs exercise detection over the window (bypassing the motion gate by treating
    the full window as one session), stores the result, and returns the workout row."""
    from app.analysis import exercise as _exercise, strain as _strain
    from app.analysis.strain import estimate_hrmax

    start, end = int(body.start_ts), int(body.end_ts)
    if end <= start:
        raise HTTPException(status_code=400, detail="end_ts must be after start_ts")
    if (end - start) > 86400:
        raise HTTPException(status_code=400, detail="window cannot exceed 24 hours")

    with psycopg.connect(cfg.db_dsn) as conn:
        # Pull streams for the window
        from app.analysis.daily import to_epoch
        hr_rows      = read.query_stream(conn, "hr",      body.device, start, end, limit=200_000)
        gravity_rows = read.query_stream(conn, "gravity", body.device, start, end, limit=200_000)
        for r in hr_rows:      r["ts"] = to_epoch(r["ts"])
        for r in gravity_rows: r["ts"] = to_epoch(r["ts"])
        profile      = read.query_profile(conn, body.device)
        resting_hr   = None

        # Try to get today's resting HR from daily metrics for a better floor
        import datetime as _dt
        day = _dt.date.fromtimestamp(start)
        daily = read.query_daily(conn, body.device, day, day)
        if daily:
            resting_hr = daily[0].get("resting_hr")

        # Get max_hr from profile if stored
        max_hr = profile.get("max_hr") if profile else None

        streams = {"hr": hr_rows, "gravity": gravity_rows}

        # Run standard detection first
        sessions = _exercise.detect_exercises(
            streams,
            resting_hr=float(resting_hr) if resting_hr else None,
            max_hr=float(max_hr) if max_hr else None,
            profile=profile,
        )

        # If detection found nothing (motion gate killed it — e.g. leg day),
        # force the full window as a single session
        if not sessions and hr_rows:
            hr_vals = [r["bpm"] for r in hr_rows if r.get("bpm")]
            if hr_vals:
                avg_hr  = sum(hr_vals) / len(hr_vals)
                peak_hr = max(hr_vals)
                dur_s   = end - start
                rhr     = float(resting_hr) if resting_hr else _strain.DEFAULT_RESTING_HR
                hr_vals_for_max = [r["bpm"] for r in hr_rows if r.get("bpm")]
                if max_hr:
                    eff_max = float(max_hr)
                    hrmax_source = "profile"
                else:
                    eff_max, hrmax_source = _strain.estimate_hrmax(
                        hr_vals_for_max, age=profile.get("age") if profile else None)
                strain_val = _strain.strain(hr_rows, max_hr=eff_max, resting_hr=rhr)
                zones, hrr_pct = _exercise._bout_intensity(hr_rows, resting_hr=rhr, max_hr=eff_max)
                sessions = [{
                    "start":         start,
                    "end":           end,
                    "avg_hr":        round(avg_hr, 2),
                    "peak_hr":       peak_hr,
                    "strain":        round(strain_val, 2) if strain_val else None,
                    "kind":          body.kind,
                    "duration_s":    dur_s,
                    "zone_time_pct": {str(z): pct for z, pct in zones.items()},
                    "avg_hrr_pct":   hrr_pct,
                    "hrmax":         eff_max,
                    "hrmax_source":  hrmax_source,
                    "calories_kcal": None,
                    "calories_kj":   None,
                }]
        else:
            # Tag all detected sessions with the provided kind
            for s in sessions:
                if body.kind:
                    s["kind"] = body.kind

        if not sessions:
            raise HTTPException(status_code=422, detail="No HR data found for that window")

        store.upsert_exercise_sessions(conn, body.device, sessions)
        conn.commit()

    return sessions

# ── Backfill workouts endpoint ────────────────────────────────────────────────

class BackfillWorkouts(BaseModel):
    device: str
    # "from"/"to" are Python keywords; declare them via alias so FastAPI/Pydantic
    # deserialises {"from": "...", "to": "..."} directly without a manual remap.
    # populate_by_name=True keeps from_date/to_date working for any internal callers.
    from_date: str | None = Field(default=None, alias="from")
    to_date:   str | None = Field(default=None, alias="to")

    model_config = {"populate_by_name": True}


@app.post("/v1/backfill-workouts", dependencies=[Depends(require_auth)])
def backfill_workouts(body: BackfillWorkouts):
    """Recompute exercise sessions (with calories) over a date range by replaying
    compute_day for each date. Idempotent — safe to re-run. May be slow for large
    ranges (runs the full daily pipeline per day). Auth-gated."""
    from_str = body.from_date
    to_str = body.to_date
    if from_str is None or to_str is None:
        raise HTTPException(status_code=422, detail="'from' and 'to' are required (YYYY-MM-DD)")
    start = _parse_date(from_str)
    end = _parse_date(to_str)
    if end < start:
        raise HTTPException(status_code=422, detail="'to' must be >= 'from'")
    results = []
    with psycopg.connect(cfg.db_dsn) as conn:
        day = start
        while day <= end:
            try:
                result = daily.compute_day(conn, body.device, day)
                conn.commit()
                results.append({"date": day.isoformat(), "status": "ok",
                                "exercises": result.get("exercises", [])})
            except Exception as exc:
                conn.rollback()
                _log.exception("backfill-workouts compute_day failed for %s %s", body.device, day)
                results.append({"date": day.isoformat(), "status": "error", "detail": str(exc)})
            day += _dt.timedelta(days=1)
    return {"recomputed": len(results), "days": results}


# ── Strain Coach endpoint ─────────────────────────────────────────────────────

def _recovery_to_target_strain(recovery: float) -> float:
    """Map recovery score (0-100) to a recommended target strain (0-21)."""
    if recovery >= 67:
        return round(14.0 + (recovery - 67) / 33.0 * 4.0, 1)
    elif recovery >= 34:
        return round(10.0 + (recovery - 34) / 32.0 * 3.0, 1)
    else:
        return round(7.0 + recovery / 33.0 * 2.0, 1)


@app.get("/v1/strain-coach", dependencies=[Depends(require_auth)])
def get_strain_coach(device: str, date: str):
    """Return strain coach data for a given date."""
    today = _parse_date(date)
    with psycopg.connect(cfg.db_dsn) as conn:
        today_rows = read.query_daily(conn, device, today, today)
        
        recovery = None
        current_strain = 0.0
        if today_rows:
            current_strain = float(today_rows[0].get("strain") or 0.0)
            recovery = today_rows[0].get("recovery")
        
        # If today has no recovery yet, look back up to 2 days for the most
        # recent computed recovery (covers the case where sleep ended "yesterday").
        if recovery is None:
            lookback_start = today - _dt.timedelta(days=2)
            past_rows = read.query_daily(conn, device, lookback_start, today)
            for row in reversed(past_rows):
                if row.get("recovery") is not None:
                    recovery = row["recovery"]
                    break
    
    if recovery is None:
        return {"date": date, "recovery": None, "target_strain": None,
                "current_strain": current_strain, "remaining": None,
                "pct_used": None, "status": "no_recovery"}
    target = _recovery_to_target_strain(float(recovery))
    remaining = round(max(0.0, target - current_strain), 1)
    pct_used = round(min(100.0, current_strain / target * 100), 1) if target > 0 else 0.0
    return {"date": date, "recovery": recovery, "target_strain": target,
            "current_strain": current_strain, "remaining": remaining,
            "pct_used": pct_used, "status": "ok"}

@app.get("/v1/batches/{batch_id}/frames", dependencies=[Depends(require_auth)])
def get_batch_frames(batch_id: str):
    with psycopg.connect(cfg.db_dsn) as conn:
        row = conn.execute(
            "SELECT file_path FROM raw_batches WHERE batch_id = %s", (batch_id,)
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="batch not found")
    return read.read_batch_frames(row[0])
