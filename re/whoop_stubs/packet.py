"""Self-contained drop-in for whoomp/scripts/packet.py.
Implements only what the RE scripts need — no external deps beyond stdlib.
"""
import struct
import zlib
from enum import IntEnum


def crc8(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) if (crc & 0x80) else (crc << 1)
            crc &= 0xFF
    return crc


class PacketType(IntEnum):
    COMMAND                  = 35
    COMMAND_RESPONSE         = 36
    REALTIME_DATA            = 40
    REALTIME_RAW_DATA        = 43
    HISTORICAL_DATA          = 47
    EVENT                    = 48
    METADATA                 = 49
    CONSOLE_LOGS             = 50
    REALTIME_IMU_DATA_STREAM = 51


class CommandNumber(IntEnum):
    SET_CLOCK             = 10
    SEND_HISTORICAL_DATA  = 22
    GET_BATTERY_LEVEL     = 26
    REBOOT_STRAP          = 29
    GET_DATA_RANGE        = 34
    START_FF_KEY_EXCHANGE = 117
    SET_FF_VALUE          = 120


class EventNumber(IntEnum):
    UNDEFINED      = 0
    ERROR          = 1
    CONSOLE_OUTPUT = 2
    BATTERY_LEVEL  = 3


class WhoopPacket:
    """Wire format: 0xAA | length:u16LE | crc8(length) | [type|seq|cmd|data...] | crc32:u32LE
    length = len(inner) + 4  (inner payload + trailing crc32 word)
    """
    def __init__(self, type_, seq: int, cmd: int, data: bytes = b""):
        self.type = type_
        self.seq  = seq
        self.cmd  = cmd
        self.data = data

    def framed_packet(self) -> bytes:
        inner  = bytes([int(self.type), self.seq, int(self.cmd)]) + self.data
        length = len(inner) + 4
        len_b  = struct.pack("<H", length)
        return (b"\xAA" + len_b + bytes([crc8(len_b)])
                + inner + struct.pack("<I", zlib.crc32(inner) & 0xFFFFFFFF))

    @classmethod
    def from_data(cls, raw: bytes) -> "WhoopPacket":
        raw = bytes(raw)
        if len(raw) < 8 or raw[0] != 0xAA:
            raise ValueError(f"bad magic: {raw[:4].hex()}")
        length = struct.unpack_from("<H", raw, 1)[0]
        inner  = raw[4:4 + length - 4]
        if len(inner) < 3:
            raise ValueError("packet too short")
        try:
            ptype = PacketType(inner[0])
        except ValueError:
            ptype = inner[0]
        return cls(ptype, inner[1], inner[2], inner[3:])

    def __repr__(self):
        try:    t = self.type.name
        except: t = str(self.type)
        try:    c = CommandNumber(self.cmd).name
        except: c = f"cmd={self.cmd}"
        return f"WhoopPacket({t} seq={self.seq} {c} data={self.data.hex()})"