#!/usr/bin/env python3
# Forge a non-desktop EDID for the headless gamescope connector (HDR when the
# config's "hdr" is true — the default — else a plain SDR/Rec.709 EDID).
#
# Spoofs Valve Index (mfg VLV / product 0x91A8) so the kernel marks the forced
# connector `non-desktop` (EDID_QUIRK_NON_DESKTOP) and KWin offers it via
# wp_drm_lease instead of extending the desktop onto it. Advertises BT2020 + PQ
# (ST2084) + a configurable peak luminance, and one DTD per (resolution, refresh).
#
# Timing math is offloaded to `cvt` (reduced-blanking when the rate is a 60-
# multiple, standard CVT otherwise) so we never hand-roll CVT. Output is gated by
# `edid-decode --check` in the Nix build, so a malformed EDID can't ship.
#
# Usage: forge_edid.py <config.json> <out.bin>
#   config.json = {"maxNit":1000,"manufacturer":"VLV","product":37288,
#                  "modes":[{"width":3840,"height":2160,"refreshRates":[60,120],
#                            "preferred":true}, ...]}

import json
import math
import subprocess
import sys


def mfg_id(s):
    # 3 letters -> 2 big-endian bytes, 5 bits each (A=1..Z=26).
    v = ((ord(s[0]) - 64) << 10) | ((ord(s[1]) - 64) << 5) | (ord(s[2]) - 64)
    return bytes([(v >> 8) & 0xFF, v & 0xFF])


def nits_to_cv(nits):
    # CTA HDR static-metadata coded value: nits = 50 * 2^(cv/32).
    if nits <= 50:
        return 0
    return max(0, min(255, round(32 * math.log2(nits / 50.0))))


def cvt(w, h, rate):
    # Reduced blanking needs a 60-multiple rate; fall back to standard CVT.
    cmds = []
    if rate % 60 == 0:
        cmds.append(["cvt", "-r", str(w), str(h), str(rate)])
    cmds.append(["cvt", str(w), str(h), str(rate)])
    for cmd in cmds:
        out = subprocess.run(cmd, capture_output=True, text=True)
        for line in out.stdout.splitlines():
            line = line.strip()
            if line.startswith("Modeline"):
                f = line.split()
                clock = float(f[2])
                hd, hss, hse, ht = (int(x) for x in f[3:7])
                vd, vss, vse, vt = (int(x) for x in f[7:11])
                flags = " ".join(f[11:])
                return {
                    "clock_khz": round(clock * 1000),
                    "hd": hd, "hbl": ht - hd, "hfp": hss - hd, "hsw": hse - hss,
                    "vd": vd, "vbl": vt - vd, "vfp": vss - vd, "vsw": vse - vss,
                    "hpol": 1 if "+hsync" in flags else 0,
                    "vpol": 1 if "+vsync" in flags else 0,
                }
    raise SystemExit(f"cvt failed for {w}x{h}@{rate}")


def dtd(t, hmm, vmm):
    clk = round(t["clock_khz"] / 10)  # 10 kHz units
    b = bytearray(18)
    b[0], b[1] = clk & 0xFF, (clk >> 8) & 0xFF
    b[2] = t["hd"] & 0xFF
    b[3] = t["hbl"] & 0xFF
    b[4] = ((t["hd"] >> 8) << 4) | (t["hbl"] >> 8)
    b[5] = t["vd"] & 0xFF
    b[6] = t["vbl"] & 0xFF
    b[7] = ((t["vd"] >> 8) << 4) | (t["vbl"] >> 8)
    b[8] = t["hfp"] & 0xFF
    b[9] = t["hsw"] & 0xFF
    b[10] = ((t["vfp"] & 0xF) << 4) | (t["vsw"] & 0xF)
    b[11] = (((t["hfp"] >> 8) & 3) << 6) | (((t["hsw"] >> 8) & 3) << 4) \
        | (((t["vfp"] >> 4) & 3) << 2) | ((t["vsw"] >> 4) & 3)
    b[12] = hmm & 0xFF
    b[13] = vmm & 0xFF
    b[14] = ((hmm >> 8) << 4) | (vmm >> 8)
    b[15] = 0  # h border
    b[16] = 0  # v border
    # digital separate sync (bits4-3=11), + h/v polarity
    b[17] = 0x18 | (t["vpol"] << 2) | (t["hpol"] << 1)
    return bytes(b)


def _pack_chromaticity(pts):
    q = {k: round(v * 1024) for k, v in pts.items()}
    b = bytearray(10)
    b[0] = ((q["rx"] & 3) << 6) | ((q["ry"] & 3) << 4) | ((q["gx"] & 3) << 2) | (q["gy"] & 3)
    b[1] = ((q["bx"] & 3) << 6) | ((q["by"] & 3) << 4) | ((q["wx"] & 3) << 2) | (q["wy"] & 3)
    b[2] = q["rx"] >> 2
    b[3] = q["ry"] >> 2
    b[4] = q["gx"] >> 2
    b[5] = q["gy"] >> 2
    b[6] = q["bx"] >> 2
    b[7] = q["by"] >> 2
    b[8] = q["wx"] >> 2
    b[9] = q["wy"] >> 2
    return bytes(b)


def chromaticity_bt2020():
    return _pack_chromaticity({"rx": 0.708, "ry": 0.292, "gx": 0.170, "gy": 0.797,
                               "bx": 0.131, "by": 0.046, "wx": 0.3127, "wy": 0.3290})


def chromaticity_rec709():
    return _pack_chromaticity({"rx": 0.640, "ry": 0.330, "gx": 0.300, "gy": 0.600,
                               "bx": 0.150, "by": 0.060, "wx": 0.3127, "wy": 0.3290})


def name_desc(text):
    d = bytearray(b"\x00\x00\x00\xfc\x00")
    d += (text[:13] + "\n").encode("ascii").ljust(13, b" ")
    return bytes(d[:18])


def range_limits(vmin, vmax, hmin, hmax, max_clk_mhz):
    d = bytearray(18)
    d[3] = 0xFD
    off = 0  # EDID 1.4 rate offsets (+255) for values that overflow one byte
    if hmax > 255:
        off |= 0x08
        hmax -= 255
    if vmax > 255:
        off |= 0x02
        vmax -= 255
    d[4] = off
    d[5], d[6], d[7], d[8] = vmin, vmax, hmin, hmax
    d[9] = math.ceil(max_clk_mhz / 10)
    d[10] = 0x01  # bare range limits, no secondary timing formula
    d[11] = 0x0A
    for i in range(12, 18):
        d[i] = 0x20
    return bytes(d)


def checksum(block):
    return (256 - (sum(block) % 256)) % 256


def main():
    cfg = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    max_cv = nits_to_cv(cfg["maxNit"])
    # hdr=false forges an SDR EDID: Rec.709 primaries, 8 bpc, and no CTA
    # colorimetry / HDR-static-metadata blocks — so the connector advertises no
    # HDR and Sunshine streams SDR. The Valve-Index non-desktop spoof stays.
    hdr = cfg.get("hdr", True)
    disp_name = "HDR Headless" if hdr else "SDR Headless"

    # Flatten to (w,h,rate) modes; preferred resolution's first rate leads.
    modes = []
    pref = None
    for r in cfg["modes"]:
        for rate in r["refreshRates"]:
            m = (r["width"], r["height"], rate)
            if r.get("preferred") and pref is None:
                pref = m
            else:
                modes.append(m)
    if pref is None:
        pref = modes.pop(0)
    modes.insert(0, pref)

    timings = [(w, h, rate, cvt(w, h, rate)) for (w, h, rate) in modes]
    max_clk = max(t["clock_khz"] for *_, t in timings) / 1000.0
    vrates = [rate for (_w, _h, rate, _t) in timings]
    hrates = [t["clock_khz"] / (t["hd"] + t["hbl"]) for (*_, t) in timings]
    vmin, vmax = min(vrates), max(vrates)
    # hmin floored to 15 kHz so the 640x480@60 established timing (31 kHz) is in range
    hmin, hmax = 15, math.ceil(max(hrates))

    # Raw DTDs cap at a 655.35 MHz pixel clock (16-bit ×10 kHz field). Above that
    # (4K@>60, ultrawide@>~100) needs VIC/DisplayID timing blocks — unsupported here.
    for (w, h, rate, t) in timings:
        if t["clock_khz"] > 655350:
            raise SystemExit(
                f"mode {w}x{h}@{rate} needs {t['clock_khz'] / 1000:.0f} MHz, over the "
                f"EDID DTD ceiling of 655 MHz. Lower the refresh or drop it "
                f"(raw-DTD reach: 4K@60, ultrawide@~100, 1440p@~165, 1080p@~240)."
            )

    # Per-mode physical size from aspect (fixed nominal width) so edid-decode's
    # aspect check passes; headless, so absolute size is arbitrary.
    def mode_size(w, h):
        return 600, round(600 * h / w)

    dtds = [dtd(t, *mode_size(w, h)) for (w, h, rate, t) in timings]
    HMM, VMM = mode_size(timings[0][0], timings[0][1])

    # ---- base block ----
    base = bytearray(128)
    base[0:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
    base[8:10] = mfg_id(cfg["manufacturer"])
    p = cfg["product"]
    base[10], base[11] = p & 0xFF, (p >> 8) & 0xFF
    base[12:16] = (0).to_bytes(4, "little")
    base[16] = 0       # week
    base[17] = 35      # year 2025 (1990+35)
    base[18] = 1       # EDID 1.4
    base[19] = 4
    base[20] = 0xB2 if hdr else 0xA2  # digital, HDMI; 10 bpc (HDR) / 8 bpc (SDR)
    base[21] = HMM // 10
    base[22] = VMM // 10
    base[23] = 0x78    # gamma 2.2
    # bit1 = preferred timing is native; bit2 = sRGB default colorspace (SDR only —
    # its Rec.709 primaries are sRGB, which EDID must signal; BT2020 must not).
    base[24] = 0x02 if hdr else 0x06
    base[25:35] = chromaticity_bt2020() if hdr else chromaticity_rec709()
    # established + standard timings: none
    base[35] = 0x20  # established: 640x480@60 (CTA requires VIC 1 to be present)
    base[36] = base[37] = 0
    for i in range(38, 54):
        base[i] = 0x01
    # 4 descriptors: preferred DTD, 2nd DTD (or name), name, range limits
    base[54:72] = dtds[0]
    if len(dtds) > 1:
        base[72:90] = dtds[1]
        base_dtd_count = 2
    else:
        base[72:90] = name_desc(disp_name)
        base_dtd_count = 1
    base[90:108] = name_desc(disp_name)
    base[108:126] = range_limits(vmin, vmax, hmin, hmax, max_clk)
    cta_dtds = dtds[base_dtd_count:]

    # ---- CTA-861 extension ----
    cta = bytearray(128)
    cta[0] = 0x02
    cta[1] = 0x03
    coll = bytearray()
    # Video Capability DB: CE + IT underscan, selectable RGB quantization
    coll += bytes([(0x07 << 5) | 2, 0x00, 0x4A])
    if hdr:
        # Colorimetry: BT2020 RGB + YCC
        coll += bytes([(0x07 << 5) | 3, 0x05, 0xC0, 0x00])
        # HDR static metadata: EOTF SDR+PQ, static type 1, max/avg/min
        coll += bytes([(0x07 << 5) | 6, 0x06, 0x05, 0x01, max_cv, max_cv, 0x00])
    dtd_start = 4 + len(coll)
    cta[3] = 0x80  # IT formats underscanned (consistent with the VCDB)
    cta[2] = dtd_start
    cta[4:4 + len(coll)] = coll
    off = dtd_start
    used = 0
    for d in cta_dtds:
        if off + 18 > 127:
            raise SystemExit(
                f"too many modes: {len(dtds)} DTDs exceed one base + CTA ext block"
            )
        cta[off:off + 18] = d
        off += 18
        used += 1

    base[126] = 1  # one extension block
    base[127] = checksum(base[:127])
    cta[127] = checksum(cta[:127])

    open(out, "wb").write(bytes(base) + bytes(cta))


if __name__ == "__main__":
    main()
