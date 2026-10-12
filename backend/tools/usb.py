"""
usb.py - carry Aaina's data to another laptop on a USB stick.

On this laptop (stick plugged in):
    .venv\\Scripts\\python tools\\usb.py save
On the other laptop (backend already installed, stick plugged in):
    .venv\\Scripts\\python tools\\usb.py load

"save" writes a folder AainaBackup on the stick with:
  aaina.db      the database (accounts, profile cards, face embeddings - never photos)
  settings.env  a copy of backend/.env (admin login, threshold, ...)
  models/       the face model, so the other laptop needs no internet to download it
"load" copies them into this laptop's backend. Whatever was there before is kept as a
".before-usb" copy, so nothing is lost by mistake.

The stick is found automatically. If it isn't (or there are two), add the letter: --drive E
Keep the stick safe: settings.env holds the admin login secrets.
"""

import argparse
import ctypes
import os
import shutil
import sqlite3
import string
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.config import BACKEND_DIR, settings  # noqa: E402

FOLDER = "AainaBackup"
ENV_FILE = os.path.join(BACKEND_DIR, ".env")
MODEL_NAME = os.getenv("FACE_MODEL", "buffalo_s")
LOCAL_MODEL = os.path.join(os.path.expanduser("~"), ".insightface", "models", MODEL_NAME)


def removable_drives():
    """Drive letters Windows calls 'removable' (USB sticks), e.g. ['E']."""
    if os.name != "nt":
        return []
    found = []
    for letter in string.ascii_uppercase:
        if ctypes.windll.kernel32.GetDriveTypeW(f"{letter}:\\") == 2:   # 2 = removable
            found.append(letter)
    return found


def pick_drive(chosen, need_backup):
    """Return the stick's backup folder path, or stop with a clear message."""
    if chosen:
        letters = [chosen.strip(":\\/ ").upper()]
    else:
        letters = removable_drives()
        if need_backup:   # when loading, prefer the stick that actually has a backup
            letters = [d for d in letters if os.path.isdir(f"{d}:\\{FOLDER}")] or letters
    if not letters:
        sys.exit("No USB stick found. Plug it in, or name it, e.g.:  tools\\usb.py save --drive E")
    if len(letters) > 1:
        sys.exit(f"More than one stick found ({', '.join(letters)}). Pick one, e.g.:  --drive {letters[0]}")
    folder = f"{letters[0]}:\\{FOLDER}"
    if need_backup and not os.path.isfile(os.path.join(folder, "aaina.db")):
        sys.exit(f"No Aaina backup on drive {letters[0]}:. Run 'tools\\usb.py save' on the other laptop first.")
    return folder


def copy_database(src, dst):
    """
    Copy a SQLite database safely using SQLite's own backup feature.
    Unlike a plain file copy, this stays correct even if the server is running.
    """
    source = sqlite3.connect(src)
    target = sqlite3.connect(dst)
    with target:
        source.backup(target)
    target.close()
    source.close()


def count_users(path):
    conn = sqlite3.connect(path)
    try:
        return conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    finally:
        conn.close()


def keep_old(path):
    """Rename an existing file to <name>.before-usb-<time> instead of overwriting it."""
    if os.path.exists(path):
        old = f"{path}.before-usb-{time.strftime('%Y%m%d-%H%M%S')}"
        os.replace(path, old)
        print(f"  old copy kept : {old}")


def save(folder):
    if not os.path.isfile(settings.db_path):
        sys.exit(f"No database yet at {settings.db_path}. Start the server once (run.py) first.")
    os.makedirs(folder, exist_ok=True)
    print(f"Saving to {folder}")

    copy_database(settings.db_path, os.path.join(folder, "aaina.db"))
    print(f"  database      : {count_users(settings.db_path)} user(s)")

    if os.path.isfile(ENV_FILE):
        shutil.copyfile(ENV_FILE, os.path.join(folder, "settings.env"))
        print("  settings      : .env copied")

    stick_model = os.path.join(folder, "models", MODEL_NAME)
    if os.path.isdir(LOCAL_MODEL) and not os.path.isdir(stick_model):
        print(f"  face model    : copying {MODEL_NAME} (about 160 MB, only the first time)...")
        shutil.copytree(LOCAL_MODEL, stick_model)
    elif os.path.isdir(stick_model):
        print(f"  face model    : already on the stick")

    with open(os.path.join(folder, "info.txt"), "w", encoding="utf-8") as f:
        f.write(f"Aaina backup saved {time.strftime('%Y-%m-%d %H:%M')}\n"
                f"Load it on another laptop with:  .venv\\Scripts\\python tools\\usb.py load\n")
    print("Done. Wait for the copy light to stop, then 'Eject' the stick before pulling it out.")


def load(folder):
    if settings.db_backend != "sqlite":
        print("Note: .env says DB_BACKEND=supabase; the loaded settings.env will decide which database is used.")
    print(f"Loading from {folder}")

    stick_db = os.path.join(folder, "aaina.db")
    os.makedirs(os.path.dirname(settings.db_path), exist_ok=True)
    if os.path.isfile(settings.db_path):
        backup = f"{settings.db_path}.before-usb-{time.strftime('%Y%m%d-%H%M%S')}"
        copy_database(settings.db_path, backup)
        print(f"  old copy kept : {backup}")
    copy_database(stick_db, settings.db_path)
    print(f"  database      : {count_users(settings.db_path)} user(s) -> {settings.db_path}")

    stick_env = os.path.join(folder, "settings.env")
    if os.path.isfile(stick_env):
        keep_old(ENV_FILE)
        shutil.copyfile(stick_env, ENV_FILE)
        print("  settings      : .env replaced with the stick's copy (same admin login as before)")

    stick_model = os.path.join(folder, "models", MODEL_NAME)
    if os.path.isdir(stick_model) and not os.path.isdir(LOCAL_MODEL):
        shutil.copytree(stick_model, LOCAL_MODEL)
        print(f"  face model    : {MODEL_NAME} installed (no internet needed)")

    print("Done. (Re)start the server:  .venv\\Scripts\\python run.py")


def main():
    parser = argparse.ArgumentParser(description="Move Aaina's data between laptops on a USB stick.")
    parser.add_argument("action", choices=["save", "load"], help="save = laptop -> stick, load = stick -> laptop")
    parser.add_argument("--drive", help="the stick's drive letter, e.g. E (normally found automatically)")
    args = parser.parse_args()
    if settings.db_backend != "sqlite" and args.action == "save":
        sys.exit("DB_BACKEND is 'supabase' in .env: the data is online already, nothing to carry.")
    folder = pick_drive(args.drive, need_backup=(args.action == "load"))
    save(folder) if args.action == "save" else load(folder)


if __name__ == "__main__":
    main()
