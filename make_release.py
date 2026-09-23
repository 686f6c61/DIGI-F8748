"""Genera los zips de la release DIGI-F8748 v0.0.1 (solo scripts) desde este repo."""
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VERSION = "v0.0.1"


def zip_into(zip_path: Path, items, executable=frozenset()):
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arcname in items:
            info = zipfile.ZipInfo.from_file(src, arcname)
            info.external_attr = (0o755 << 16) if arcname in executable else (0o644 << 16)
            z.writestr(info, src.read_bytes())
    print(f"built {zip_path.name} ({zip_path.stat().st_size // 1024} KB)")


leeme = ROOT / "LEEME.md"
sh_cli = ROOT / "DIGI-F8748-linux/digi-f8748.sh"
starter = ROOT / "DIGI-F8748-linux/start.sh"
ps1 = ROOT / "DIGI-F8748-windows/digi-f8748.ps1"
py_cli = ROOT / "DIGI-F8748-windows/digi-f8748.py"
req = ROOT / "DIGI-F8748-windows/requirements.txt"
bat_py = ROOT / "DIGI-F8748-windows/digi-f8748.bat"
bat_ps1 = ROOT / "DIGI-F8748-windows/digi-f8748-ps1.bat"

zip_into(ROOT / f"DIGI-F8748-{VERSION}-shell-universal.zip", [
    (sh_cli, "digi-f8748.sh"), (starter, "start.sh"), (leeme, "LEEME.md"),
], executable={"digi-f8748.sh", "start.sh"})

zip_into(ROOT / f"DIGI-F8748-{VERSION}-macos.zip", [
    (ROOT / "DIGI-F8748-macos/digi-f8748.sh", "DIGI-F8748-macos/digi-f8748.sh"),
    (ROOT / "DIGI-F8748-macos/start.sh", "DIGI-F8748-macos/start.sh"),
    (ROOT / "DIGI-F8748-macos/digi-f8748.py", "DIGI-F8748-macos/digi-f8748.py"),
    (req, "DIGI-F8748-macos/requirements.txt"),
    (leeme, "DIGI-F8748-macos/LEEME.md"),
], executable={"digi-f8748.sh", "start.sh"})

zip_into(ROOT / f"DIGI-F8748-{VERSION}-linux.zip", [
    (ROOT / "DIGI-F8748-linux/digi-f8748.sh", "DIGI-F8748-linux/digi-f8748.sh"),
    (ROOT / "DIGI-F8748-linux/start.sh", "DIGI-F8748-linux/start.sh"),
    (ROOT / "DIGI-F8748-linux/digi-f8748.py", "DIGI-F8748-linux/digi-f8748.py"),
    (req, "DIGI-F8748-linux/requirements.txt"),
    (leeme, "DIGI-F8748-linux/LEEME.md"),
], executable={"digi-f8748.sh", "start.sh"})

zip_into(ROOT / f"DIGI-F8748-{VERSION}-windows.zip", [
    (ps1, "DIGI-F8748-windows/digi-f8748.ps1"),
    (bat_ps1, "DIGI-F8748-windows/digi-f8748-ps1.bat"),
    (py_cli, "DIGI-F8748-windows/digi-f8748.py"),
    (bat_py, "DIGI-F8748-windows/digi-f8748.bat"),
    (req, "DIGI-F8748-windows/requirements.txt"),
    (leeme, "DIGI-F8748-windows/LEEME.md"),
])

zip_into(ROOT / f"DIGI-F8748-{VERSION}-source.zip", [
    (py_cli, "digi-f8748.py"),
    (sh_cli, "digi-f8748.sh"),
    (ps1, "digi-f8748.ps1"),
    (req, "requirements.txt"),
    (leeme, "LEEME.md"),
])

print("\nRelease bundles in:", ROOT)
