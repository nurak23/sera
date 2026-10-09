#!/usr/bin/env python3
"""Anonymise IEEE 802.15.4 / Zigbee pcaps while preserving byte structure.

usage: anonymize_pcap.py MAP IN.pcap OUT.pcap TK_FRAMES
  MAP       text file, lines "REAL_EUI64 REPLACEMENT_EUI64" (colon hex, display order)
  TK_FRAMES comma-separated 1-based frame numbers of APS Transport-Key frames
            (73-byte frames); their encrypted key field is overwritten.
Steps: (1) substitute EUI-64s (little-endian on the wire); (2) overwrite the
ciphertext of the Transport-Key frames with 0xEE (CTR mode: the key cannot be
recovered from the remaining bytes); (3) recompute the CRC-16/KERMIT FCS.
"""
import sys
from scapy.utils import rdpcap, wrpcap
from scapy.packet import Raw

DLT_IEEE802_15_4 = 195  # with FCS


def crc16_kermit(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc


def eui(s):
    return bytes(int(x, 16) for x in s.split(":"))[::-1]


def main(mapf, inp, outp, tk):
    pairs = [l.split() for l in open(mapf) if l.strip() and not l.startswith("#")]
    pairs = [(eui(a), eui(b)) for a, b in pairs]
    tkset = {int(x) for x in tk.split(",") if x}
    pk = rdpcap(inp)
    out = []
    for i, p in enumerate(pk, 1):
        d = bytearray(bytes(p))
        for a, b in pairs:
            j = d.find(a)
            while j != -1:
                d[j:j + 8] = b
                j = d.find(a, j + 8)
        if i in tkset:
            if len(d) != 73:
                raise SystemExit(f"frame {i} is {len(d)} B, expected 73")
            for k in range(32, len(d) - 2):
                d[k] = 0xEE
        if len(d) > 2:
            c = crc16_kermit(bytes(d[:-2]))
            d[-2:] = bytes([c & 255, c >> 8])
        q = Raw(bytes(d))
        q.time = p.time
        out.append(q)
    wrpcap(outp, out, linktype=DLT_IEEE802_15_4)
    print(f"{inp}: {len(out)} frames -> {outp}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
