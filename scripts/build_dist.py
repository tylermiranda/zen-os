#!/usr/bin/env python3
"""Build dist/zenos.koplugin and dist/zenos.koplugin.zip matching build.sh rules."""

from __future__ import annotations

import os
import shutil
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DIST_DIR = REPO_ROOT / "dist"
CANONICAL_NAME = "zenos.koplugin"

EXCLUDED_DIRS = {
    ".git",
    ".github",
    ".vscode",
    "dist",
    "spec",
    "docs",
    "icon-packs",
    "scripts",
    "extras",
    "_includes",
    ".venv",
    "__pycache__",
}

ALLOWED_SH = {
    "kindle-launcher/ZenReader.sh",
    "modules/global/kindle_restore_screen.sh",
}

ALLOWED_MD = {
    "LICENSE.md",
    "modules/filebrowser/metadata/LICENSES.md",
}


def should_include(rel_posix: str) -> bool:
    parts = rel_posix.split("/")
    if any(p in EXCLUDED_DIRS or p.startswith(".") for p in parts):
        return False
    if rel_posix.startswith("images/") and rel_posix != "images/ornate-cover-frame.svg":
        return False
    name = parts[-1]
    if name.startswith("._"):
        return False
    if name.endswith(".sh") and rel_posix not in ALLOWED_SH:
        return False
    if name.endswith(".md") and rel_posix not in ALLOWED_MD:
        return False
    if name.endswith((".py", ".zip", ".luarocks", ".luacheckrc", ".yml", ".yaml")):
        return False
    if rel_posix == "_config.yml":
        return False
    return True


def main() -> None:
    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    payload_dir = DIST_DIR / CANONICAL_NAME
    payload_dir.mkdir(parents=True, exist_ok=True)

    count = 0
    for root, dirs, files in os.walk(REPO_ROOT):
        rel_root = Path(root).relative_to(REPO_ROOT)
        rel_root_posix = "" if rel_root == Path(".") else rel_root.as_posix()
        dirs[:] = [
            d
            for d in dirs
            if d not in EXCLUDED_DIRS
            and not d.startswith(".")
            and not d.endswith(".yml")
            and not (rel_root_posix == "images")
        ]
        for fn in files:
            rel_posix = fn if not rel_root_posix else f"{rel_root_posix}/{fn}"
            if not should_include(rel_posix):
                continue
            src = Path(root) / fn
            dst = payload_dir / rel_posix
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            count += 1

    zip_path = DIST_DIR / f"{CANONICAL_NAME}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for file_path in sorted(payload_dir.rglob("*")):
            if file_path.is_file():
                arcname = f"{CANONICAL_NAME}/{file_path.relative_to(payload_dir).as_posix()}"
                zf.write(file_path, arcname)

    print(f"Built {payload_dir} ({count} files) and {zip_path}")


if __name__ == "__main__":
    main()
