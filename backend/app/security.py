"""
security.py - passwords, login tokens and the admin one-time code.

- Passwords are never stored. We store a salted PBKDF2 hash (built into Python).
- Login tokens are random strings. The database only keeps a SHA-256 hash of each token,
  so even someone who copies the database file cannot log in as anyone.
- Admin tokens live in memory only: restarting the server logs the admin out (that's fine).
- A tiny in-memory limiter blocks password guessing (5 tries per 5 minutes per account).
"""

import hashlib
import hmac
import secrets
import time

import pyotp

from app import db
from app.config import settings

PBKDF2_ROUNDS = 200_000


# ---------- passwords ----------

def hash_password(password):
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ROUNDS).hex()
    return f"pbkdf2${PBKDF2_ROUNDS}${salt}${digest}"


def check_password(password, stored):
    try:
        _, rounds, salt, digest = stored.split("$")
    except ValueError:
        return False
    test = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), int(rounds)).hex()
    return hmac.compare_digest(test, digest)   # compare_digest avoids timing tricks


# ---------- user login tokens ----------

def _hash_token(token):
    return hashlib.sha256(token.encode()).hexdigest()


def new_user_session(user_id, borrowed):
    """Create a login token. Borrowed-phone logins expire after a short idle time."""
    token = secrets.token_urlsafe(32)
    expires = db.now() + settings.session_days * 86400
    db.create_session(_hash_token(token), user_id, borrowed, expires)
    return token


def user_from_token(token):
    """Return the user id for a valid token, or None. Also refreshes 'last used'."""
    session = db.get_session(_hash_token(token))
    if session is None:
        return None
    t = db.now()
    idle_limit = settings.borrowed_idle_minutes * 60
    if t > session["expires_at"] or (session["borrowed"] and t - session["last_used"] > idle_limit):
        db.delete_session(session["token_hash"])
        return None
    db.touch_session(session["token_hash"])
    return session["user_id"]


def end_user_session(token):
    db.delete_session(_hash_token(token))


# ---------- admin ----------

_admin_tokens = {}  # token hash -> expiry time (memory only)


def admin_configured():
    return bool(settings.admin_id and settings.admin_password_hash and settings.admin_totp_secret)


def check_admin_login(admin_id, password, otp):
    if not admin_configured():
        return False
    id_ok = hmac.compare_digest(admin_id, settings.admin_id)
    pw_ok = check_password(password, settings.admin_password_hash)
    # valid_window=1 also accepts the previous/next 30-second code (phone clock drift).
    otp_ok = pyotp.TOTP(settings.admin_totp_secret).verify(otp.strip(), valid_window=1)
    return id_ok and pw_ok and otp_ok


def new_admin_session():
    token = secrets.token_urlsafe(32)
    _admin_tokens[_hash_token(token)] = time.time() + settings.admin_session_hours * 3600
    return token


def is_admin_token(token):
    expiry = _admin_tokens.get(_hash_token(token))
    if expiry is None:
        return False
    if time.time() > expiry:
        _admin_tokens.pop(_hash_token(token), None)
        return False
    return True


def end_admin_session(token):
    _admin_tokens.pop(_hash_token(token), None)


# ---------- password-guessing limiter ----------

_failures = {}  # key -> list of failure times
MAX_FAILURES, WINDOW_SECONDS = 5, 300


def too_many_failures(key):
    recent = [t for t in _failures.get(key, []) if time.time() - t < WINDOW_SECONDS]
    _failures[key] = recent
    return len(recent) >= MAX_FAILURES


def record_failure(key):
    _failures.setdefault(key, []).append(time.time())


def clear_failures(key):
    _failures.pop(key, None)
