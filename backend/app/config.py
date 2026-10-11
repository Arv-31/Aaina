"""
config.py - every setting the backend uses, read from backend/.env in one place.

Other files do `from app.config import settings` and read e.g. settings.db_path.
Secrets (admin password hash, one-time-code secret) live only in .env, never in code or Git.
"""

import os

from dotenv import load_dotenv

# Find backend/.env no matter which folder the server was started from.
BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(BACKEND_DIR, ".env"))


def _int(name, default):
    return int(os.getenv(name, default))


class Settings:
    # Where the SQLite database file lives (relative paths are inside backend/).
    db_path = os.getenv("DB_PATH", "data/aaina.db")
    if not os.path.isabs(db_path):
        db_path = os.path.join(BACKEND_DIR, db_path)

    # Server address. 0.0.0.0 = reachable from the phone on the same hotspot/Wi-Fi.
    host = os.getenv("HOST", "0.0.0.0")
    port = _int("PORT", "8000")

    # Logins: "remember me" lasts days; a "borrowed phone" login dies after minutes of no use.
    session_days = _int("SESSION_DAYS", "30")
    borrowed_idle_minutes = _int("BORROWED_IDLE_MINUTES", "10")
    admin_session_hours = _int("ADMIN_SESSION_HOURS", "8")

    # Admin login (filled in by tools/setup_admin.py). Empty = admin login switched off.
    admin_id = os.getenv("ADMIN_ID", "")
    admin_password_hash = os.getenv("ADMIN_PASSWORD_HASH", "")
    admin_totp_secret = os.getenv("ADMIN_TOTP_SECRET", "")

    # Web pages allowed to call this API from a browser (the admin console).
    # Comma-separated. "*" allows any origin, which is fine on a private expo hotspot.
    cors_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]

    # Enrollment quality checks (extra C).
    enroll_min_photos = _int("ENROLL_MIN_PHOTOS", "3")
    enroll_max_photos = _int("ENROLL_MAX_PHOTOS", "5")
    blur_min = float(os.getenv("BLUR_MIN", "40"))          # higher = stricter about blur
    brightness_min = _int("BRIGHTNESS_MIN", "50")          # 0-255, too dark below this
    brightness_max = _int("BRIGHTNESS_MAX", "215")         # 0-255, too bright above this
    # Enrollment photos must match each other at least this well (lower than MATCH_THRESHOLD
    # because left/right head turns score a bit lower against a straight-on photo).
    same_set_min = float(os.getenv("SAME_SET_MIN", "0.30"))
    max_upload_mb = _int("MAX_UPLOAD_MB", "6")


settings = Settings()
