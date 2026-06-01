"""Fast V24 flag verification — total runtime ~75 seconds.

Connects, polls GET_DATA_RANGE twice with a 60s gap, and checks whether the
write pointer advanced. Advancing write pointer = the band is writing new flash
records (V24 if enable_write_r24_packets is ON, V5/V7/V9 if OFF).

Then does a short SEND_HISTORICAL_DATA burst (10s) and counts type-47 version
bytes to confirm V24 vs V5/V7/V9 directly.

Run this ~40s after enable_dataproducts.py finishes (after the reboot reconnects).
No mode changes, no trim, no ack. Read-only except for the short offload probe.

Usage:
    python re/verify_v24_fast.py
"""
import asyncio
import struct
import sys
import time
from collections import Counter

sys.path.insert(0, "whoomp/scripts")
from packet import WhoopPacket, PacketType, CommandNumber  # noqa: E402
from bleak import BleakClient, BleakScanner  # noqa: E402

from device_config import DEVICE_UUID as ADDR

CMD_TO   = "61080002-8d6d-82b8-614a-1c8cb0f8dcc6"
CMD_FROM = "61080003-8d6d-82b8-614a-1c8cb0f8dcc6"
EVENTS   = "61080004-8d6d-82b8-614a-1c8cb0f8dcc6"
DATA     = "61080005-8d6d-82b8-614a-1c8cb0f8dcc6"

resp_q: asyncio.Queue = asyncio.Queue()

# --- type-47 version byte capture ---
hist_buf    = b""
hist_need   = 0
hist_versions: Counter = Counter()   # version_byte -> count
hist_frames = 0


def data_cb(_, d):
    global hist_buf, hist_need, hist_frames
    raw = bytes(d)
    if hist_need == 0:
        if len(raw) >= 3 and raw[0] == 0xAA:
            total = struct.unpack_from("<H", raw, 1)[0] + 4
            if len(raw) >= total:
                _parse_frame(raw[:total])
            else:
                hist_buf, hist_need = raw, total
    else:
        hist_buf += raw
        if len(hist_buf) >= hist_need:
            _parse_frame(hist_buf[:hist_need])
            hist_buf, hist_need = b"", 0


def _parse_frame(frame):
    global hist_frames
    try:
        pkt = frame[4:]          # skip 0xAA + length(2) + header_crc
        pkt_type = pkt[0]
        if pkt_type == 47:       # HISTORICAL_DATA
            hist_frames += 1
            ver = pkt[1]         # version byte (seq field reused as version in type-47)
            hist_versions[ver] += 1
    except Exception:
        pass


def resp_cb(_, d):
    try:
        resp_q.put_nowait(WhoopPacket.from_data(bytes(d)))
    except Exception:
        pass


async def send(c, cmd, payload=b"\x00", resp=True):
    pkt = WhoopPacket(PacketType.COMMAND, 10, cmd, data=payload).framed_packet()
    await c.write_gatt_char(CMD_TO, pkt, response=resp)


async def get_write_pointer(c) -> int | None:
    """Send GET_DATA_RANGE and return the write pointer (last u32 LE in response)."""
    while not resp_q.empty():
        resp_q.get_nowait()
    await send(c, CommandNumber.GET_DATA_RANGE, b"\x00")
    deadline = time.time() + 5.0
    while time.time() < deadline:
        try:
            pkt = await asyncio.wait_for(resp_q.get(), timeout=deadline - time.time())
            data = bytes(pkt.data)
            # strip 2-byte status prefix if present
            body = data[2:] if len(data) > 2 else data
            u32s = [struct.unpack_from("<I", body, i)[0]
                    for i in range(0, len(body) - 3, 4)]
            if not u32s:
                return None
            print(f"  GET_DATA_RANGE raw u32s: {u32s}", flush=True)
            return u32s[-1]   # write pointer is the last word
        except asyncio.TimeoutError:
            break
    return None


def version_label(ver: int) -> str:
    return {5: "V5 (HR+RR only)", 7: "V7 (HR+RR only)", 9: "V9 (HR+RR only)",
            12: "V12 (partial biometric)", 24: "V24 (full biometric ✓)"}.get(ver, f"V{ver} (unknown)")


async def main():
    print("=== verify_v24_fast.py ===", flush=True)
    print(f"Scanning for strap {ADDR} ...", flush=True)
    dev = await BleakScanner.find_device_by_address(ADDR, timeout=20.0)
    if dev is None:
        print("ERROR: strap not found. Is the phone BT off? Is the strap nearby?")
        return

    async with BleakClient(dev) as c:
        await c.start_notify(CMD_FROM, resp_cb)
        await c.start_notify(EVENTS, lambda _, d: None)
        await c.start_notify(DATA, data_cb)

        # Bond
        await send(c, CommandNumber.GET_BATTERY_LEVEL, b"\x00")
        await asyncio.sleep(1.5)
        print("(bonded)\n", flush=True)

        # ── Poll 1 ────────────────────────────────────────────────────────────
        print("── POLL 1: GET_DATA_RANGE ──", flush=True)
        ptr1 = await get_write_pointer(c)
        t1 = time.time()
        if ptr1 is None:
            print("  ERROR: no response — strap may not be ready yet. Wait 30s and retry.")
            return
        print(f"  write pointer: {ptr1}\n", flush=True)

        # ── Wait 60 s ─────────────────────────────────────────────────────────
        print("Waiting 60s for the band to write flash records ...", flush=True)
        for remaining in range(60, 0, -10):
            print(f"  {remaining}s ...", flush=True)
            await asyncio.sleep(10)

        # ── Poll 2 ────────────────────────────────────────────────────────────
        print("\n── POLL 2: GET_DATA_RANGE ──", flush=True)
        ptr2 = await get_write_pointer(c)
        t2 = time.time()
        if ptr2 is None:
            print("  ERROR: no response on second poll.")
            return
        elapsed = t2 - t1
        delta   = ptr2 - ptr1
        rate    = delta / elapsed if elapsed > 0 else 0
        print(f"  write pointer: {ptr2}", flush=True)
        print(f"  delta: {delta} records in {elapsed:.0f}s  ({rate:.2f} rec/s)\n", flush=True)

        # ── Short offload probe — read version bytes directly ─────────────────
        print("── OFFLOAD PROBE: 10s SEND_HISTORICAL_DATA (no ack/trim) ──", flush=True)
        hist_versions.clear()
        hist_frames_before = hist_frames
        await send(c, CommandNumber.SEND_HISTORICAL_DATA, b"\x00", resp=True)
        await asyncio.sleep(10)
        frames_captured = hist_frames - hist_frames_before
        print(f"  type-47 frames captured: {frames_captured}", flush=True)
        if hist_versions:
            print("  version byte breakdown:", flush=True)
            for ver, count in sorted(hist_versions.items()):
                print(f"    {version_label(ver)}: {count} records", flush=True)
        else:
            print("  no type-47 frames received (band may need >60s to accumulate records)", flush=True)

        # ── VERDICT ───────────────────────────────────────────────────────────
        print("\n════════════════ VERDICT ════════════════", flush=True)
        v24_count = hist_versions.get(24, 0)
        old_count  = sum(hist_versions.get(v, 0) for v in (5, 7, 9))

        if delta <= 0:
            print("✗ FAIL — write pointer did NOT advance.", flush=True)
            print("  enable_write_r24_packets flag may not have taken effect.", flush=True)
            print("  Check: did enable_dataproducts.py complete + reboot? Is the strap being worn?", flush=True)
        elif v24_count > 0:
            print(f"✓ PASS — write pointer +{delta} records, and V24 frames confirmed ({v24_count} records).", flush=True)
            print("  Gravity / SpO2 / skin-temp / resp data will now flow into SQLite.", flush=True)
        elif old_count > 0:
            print(f"⚠ PARTIAL — write pointer +{delta} records, but only V5/V7/V9 frames seen ({old_count} records).", flush=True)
            print("  Flash is writing, but V24 flag may still be off.", flush=True)
            print("  Possible: band needs a longer wear before new V24 records appear at the offload cursor.", flush=True)
            print("  Try: wait 5 more minutes and run this script again.", flush=True)
        else:
            print(f"? INCONCLUSIVE — write pointer +{delta} records but no type-47 frames in probe window.", flush=True)
            print("  The band may not have served historical data yet. Re-run in 5 minutes.", flush=True)

        print("════════════════════════════════════════", flush=True)


asyncio.run(main())
