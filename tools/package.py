"""Builds the zip for CurseForge and GitHub releases: dist/Earshot-<version>.zip.

The zip holds one folder, Earshot, which is what goes in Interface\\AddOns. It also gets
LICENSE and CHANGELOG.md from the top of the repo.

    python tools/package.py              run the tests, then build
    python tools/package.py --no-tests   build only

The version comes from `## Version` in Earshot/Earshot.toc. Every file the TOC lists has to
be there, or nothing is built.
"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "Earshot"
EXTRA = ["LICENSE", "CHANGELOG.md"]  # from the top of the repo, into the Earshot folder
SKIP = {".DS_Store", "Thumbs.db", "desktop.ini"}


def toc_text():
    return (ADDON / "Earshot.toc").read_text(encoding="utf-8")


def version():
    found = re.search(r"^## Version:\s*(\S+)\s*$", toc_text(), re.MULTILINE)
    if not found:
        sys.exit("No '## Version:' line in Earshot.toc")
    return found.group(1)


def missing_files():
    missing = []
    for line in toc_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            if not (ADDON / line.replace("\\", "/")).is_file():
                missing.append(line)
    return missing


def main():
    if "--no-tests" not in sys.argv[1:]:
        if subprocess.run([sys.executable, str(ROOT / "tests" / "run.py")]).returncode != 0:
            sys.exit("The tests failed, so nothing was built.")
    missing = missing_files()
    if missing:
        sys.exit("Earshot.toc lists files that aren't there: " + ", ".join(missing))
    for name in EXTRA:
        if not (ROOT / name).is_file():
            sys.exit(f"{name} is missing from the top of the repo.")

    out = ROOT / "dist" / f"Earshot-{version()}.zip"
    out.parent.mkdir(exist_ok=True)
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zipped:
        for path in sorted(ADDON.rglob("*")):
            relative = path.relative_to(ADDON)
            if path.is_dir() or path.name in SKIP or any(part.startswith(".") for part in relative.parts):
                continue
            zipped.write(path, "Earshot/" + relative.as_posix())
            count += 1
        for name in EXTRA:
            zipped.write(ROOT / name, "Earshot/" + name)
            count += 1
    print(f"Built {out.relative_to(ROOT)} ({count} files).")


if __name__ == "__main__":
    main()
