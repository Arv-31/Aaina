"""
db.py - all database reads and writes, in one place (SQLite, built into Python).

Tables:
  users            account + profile card fields + privacy switches
  face_embeddings  512 numbers per enrolled face photo (never the photo itself)
  consents         when the user accepted which consent text
  sessions         login tokens (only a hash of each token is stored)
  recognitions     time + matched user id for the admin overview.
                   "Unknown" faces store only the time: nothing about the person.

Deleting a user deletes their embeddings, consents and sessions too (ON DELETE CASCADE).
Milestone 3 can add Supabase behind these same functions; the rest of the app won't change.
"""

import json
import os
import sqlite3
import time
import uuid

import numpy as np

from app.config import settings

# Card fields a user may switch off individually (extra B). Name + LinkedIn are always shown.
SHAREABLE_FIELDS = [
    "student_status", "college", "course_year", "job_title", "company",
    "skills", "github_url", "instagram_url", "portfolio_url",
]
PROFILE_FIELDS = ["name", "linkedin_url"] + SHAREABLE_FIELDS

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id             TEXT PRIMARY KEY,
    username       TEXT UNIQUE NOT NULL,
    password_hash  TEXT NOT NULL,
    name           TEXT NOT NULL,
    linkedin_url   TEXT NOT NULL,
    student_status TEXT,
    college        TEXT,
    course_year    TEXT,
    job_title      TEXT,
    company        TEXT,
    skills         TEXT,            -- JSON list, e.g. ["Flutter", "Python"]
    github_url     TEXT,
    instagram_url  TEXT,
    portfolio_url  TEXT,
    visible        INTEGER NOT NULL DEFAULT 1,   -- 0 = "hide me" (shows as Unknown)
    share          TEXT NOT NULL DEFAULT '{}',   -- JSON {field: false} for hidden fields
    qr_token       TEXT UNIQUE NOT NULL,         -- QR fallback (extra A)
    created_at     INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS face_embeddings (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    embedding  BLOB NOT NULL,       -- 512 float32 numbers
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS consents (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    consent_version TEXT NOT NULL,
    accepted_at     INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    borrowed   INTEGER NOT NULL,    -- 1 = borrowed-phone login (short idle timeout)
    created_at INTEGER NOT NULL,
    last_used  INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS recognitions (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    at      INTEGER NOT NULL,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE   -- NULL = Unknown
);
"""


def now():
    return int(time.time())


def connect():
    """Open the database. Each request gets its own short-lived connection."""
    os.makedirs(os.path.dirname(settings.db_path), exist_ok=True)
    conn = sqlite3.connect(settings.db_path)
    conn.row_factory = sqlite3.Row             # rows behave like dicts: row["name"]
    conn.execute("PRAGMA foreign_keys = ON")   # needed for ON DELETE CASCADE in SQLite
    return conn


def init_db():
    with connect() as conn:
        conn.executescript(SCHEMA)


def _user_dict(row):
    """Turn a database row into a plain dict with skills/share decoded from JSON."""
    if row is None:
        return None
    user = dict(row)
    user["skills"] = json.loads(user["skills"]) if user["skills"] else []
    user["share"] = json.loads(user["share"] or "{}")
    user["visible"] = bool(user["visible"])
    return user


# ---------- users ----------

def create_user(username, password_hash, profile, consent_version):
    user_id = str(uuid.uuid4())
    with connect() as conn:
        conn.execute(
            f"INSERT INTO users (id, username, password_hash, {', '.join(PROFILE_FIELDS)}, qr_token, created_at) "
            f"VALUES (?, ?, ?, {', '.join('?' for _ in PROFILE_FIELDS)}, ?, ?)",
            [user_id, username, password_hash]
            + [_encode(f, profile.get(f)) for f in PROFILE_FIELDS]
            + [uuid.uuid4().hex, now()],
        )
        conn.execute(
            "INSERT INTO consents (id, user_id, consent_version, accepted_at) VALUES (?, ?, ?, ?)",
            (str(uuid.uuid4()), user_id, consent_version, now()),
        )
    return user_id


def _encode(field, value):
    if field == "skills":
        return json.dumps(value or [])
    return value


def get_user(user_id):
    with connect() as conn:
        return _user_dict(conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone())


def get_user_by_username(username):
    with connect() as conn:
        return _user_dict(conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone())


def get_user_by_qr(qr_token):
    with connect() as conn:
        return _user_dict(conn.execute("SELECT * FROM users WHERE qr_token = ?", (qr_token,)).fetchone())


def update_user(user_id, changes):
    """changes: dict of column -> new value (only known columns are allowed)."""
    allowed = set(PROFILE_FIELDS) | {"visible", "share", "qr_token"}
    sets, values = [], []
    for field, value in changes.items():
        if field not in allowed:
            continue
        if field == "share":
            value = json.dumps(value)
        elif field == "visible":
            value = int(bool(value))
        else:
            value = _encode(field, value)
        sets.append(f"{field} = ?")
        values.append(value)
    if sets:
        with connect() as conn:
            conn.execute(f"UPDATE users SET {', '.join(sets)} WHERE id = ?", values + [user_id])


def delete_user(user_id):
    """Delete-my-data: the cascade removes embeddings, consents, sessions and log rows."""
    with connect() as conn:
        cur = conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
        return cur.rowcount > 0


def list_users(search=""):
    with connect() as conn:
        rows = conn.execute(
            "SELECT u.*, (SELECT COUNT(*) FROM face_embeddings e WHERE e.user_id = u.id) AS face_count "
            "FROM users u WHERE u.name LIKE ? OR u.username LIKE ? ORDER BY u.created_at DESC",
            (f"%{search}%", f"%{search}%"),
        ).fetchall()
    users = []
    for row in rows:
        user = _user_dict(row)
        user["face_count"] = row["face_count"]
        users.append(user)
    return users


# ---------- face embeddings ----------

def replace_embeddings(user_id, embeddings):
    """Store new embeddings for a user, replacing any older ones (re-enrolling)."""
    with connect() as conn:
        conn.execute("DELETE FROM face_embeddings WHERE user_id = ?", (user_id,))
        for emb in embeddings:
            conn.execute(
                "INSERT INTO face_embeddings (id, user_id, embedding, created_at) VALUES (?, ?, ?, ?)",
                (str(uuid.uuid4()), user_id, np.asarray(emb, dtype=np.float32).tobytes(), now()),
            )


def count_embeddings(user_id):
    with connect() as conn:
        return conn.execute("SELECT COUNT(*) FROM face_embeddings WHERE user_id = ?", (user_id,)).fetchone()[0]


def load_visible_embeddings():
    """Return (user_ids list, matrix N x 512) for everyone who is not hidden."""
    with connect() as conn:
        rows = conn.execute(
            "SELECT e.user_id, e.embedding FROM face_embeddings e "
            "JOIN users u ON u.id = e.user_id WHERE u.visible = 1"
        ).fetchall()
    ids = [r["user_id"] for r in rows]
    matrix = np.array([np.frombuffer(r["embedding"], dtype=np.float32) for r in rows]) if rows else np.zeros((0, 512), np.float32)
    return ids, matrix


# ---------- sessions ----------

def create_session(token_hash, user_id, borrowed, expires_at):
    with connect() as conn:
        conn.execute(
            "INSERT INTO sessions (token_hash, user_id, borrowed, created_at, last_used, expires_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (token_hash, user_id, int(borrowed), now(), now(), expires_at),
        )


def get_session(token_hash):
    with connect() as conn:
        row = conn.execute("SELECT * FROM sessions WHERE token_hash = ?", (token_hash,)).fetchone()
        return dict(row) if row else None


def touch_session(token_hash):
    with connect() as conn:
        conn.execute("UPDATE sessions SET last_used = ? WHERE token_hash = ?", (now(), token_hash))


def delete_session(token_hash):
    with connect() as conn:
        conn.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash,))


# ---------- recognition log (admin overview) ----------

def log_recognition(user_id):
    with connect() as conn:
        conn.execute("INSERT INTO recognitions (at, user_id) VALUES (?, ?)", (now(), user_id))


def overview():
    t = now()
    start_of_day = t - (t % 86400)
    with connect() as conn:
        one = lambda sql, *a: conn.execute(sql, a).fetchone()[0]  # noqa: E731
        recent = conn.execute(
            "SELECT r.at, u.name FROM recognitions r JOIN users u ON u.id = r.user_id "
            "ORDER BY r.at DESC LIMIT 20"
        ).fetchall()
        return {
            "users_total": one("SELECT COUNT(*) FROM users"),
            "users_hidden": one("SELECT COUNT(*) FROM users WHERE visible = 0"),
            "users_with_face": one("SELECT COUNT(DISTINCT user_id) FROM face_embeddings"),
            "scans_last_10_min": one("SELECT COUNT(*) FROM recognitions WHERE at >= ?", t - 600),
            "matches_today": one("SELECT COUNT(*) FROM recognitions WHERE user_id IS NOT NULL AND at >= ?", start_of_day),
            "unknown_today": one("SELECT COUNT(*) FROM recognitions WHERE user_id IS NULL AND at >= ?", start_of_day),
            "recent_matches": [{"name": r["name"], "at": r["at"]} for r in recent],
        }
