"""
db.py - all database reads and writes, in one place (SQLite, built into Python).

Tables:
  users            account + profile card fields + privacy switches
  face_embeddings  512 numbers per enrolled face photo (never the photo itself)
  consents         when the user accepted which consent text
  sessions         login tokens (only a hash of each token is stored)
  recognitions     time + matched user id for the admin overview.
                   "Unknown" faces store only the time: nothing about the person.
  events           event mode (extra E): event name + auto-delete date
  app_state        small key/value settings, e.g. which event is running now

Deleting a user deletes their embeddings, consents and sessions too (ON DELETE CASCADE).

Two engines, picked by DB_BACKEND in .env (the rest of the app never knows which one runs):
  sqlite    a file on this laptop (default; works with no internet at the expo)
  supabase  Supabase's free cloud Postgres. The SQL below is written once, SQLite-style
            with "?" placeholders; for Postgres it is translated in _PgConn.
"""

import json
import os
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager

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
    event          TEXT,                         -- event they signed up at (NULL = none)
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
CREATE TABLE IF NOT EXISTS events (
    name         TEXT PRIMARY KEY,
    delete_after INTEGER,           -- unix time; users of this event are wiped after it
    created_at   INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS app_state (
    key   TEXT PRIMARY KEY,
    value TEXT
);
"""


def now():
    return int(time.time())


def using_postgres():
    return settings.db_backend == "supabase"


# Postgres types for the same tables (SQLite is relaxed about types, Postgres is not).
# BIGINT because unix times pass the 32-bit limit in 2038.
PG_SCHEMA = (SCHEMA
             .replace("INTEGER PRIMARY KEY AUTOINCREMENT", "BIGSERIAL PRIMARY KEY")
             .replace("INTEGER", "BIGINT")
             .replace("BLOB", "BYTEA"))


class _PgConn:
    """Makes a Postgres connection accept the same SQL as SQLite ("?" -> "%s")."""

    def __init__(self, conn):
        self.conn = conn

    def execute(self, sql, params=None):
        return self.conn.execute(sql.replace("?", "%s"), params or None)


_pool = None
_pool_lock = threading.Lock()


def _pg_pool():
    """A few open connections kept ready, so each request skips the slow internet handshake."""
    global _pool
    with _pool_lock:
        if _pool is None:
            # Imported here so the default SQLite setup never needs these packages.
            from psycopg.rows import dict_row
            from psycopg_pool import ConnectionPool

            if not settings.supabase_db_url:
                raise RuntimeError("DB_BACKEND=supabase but SUPABASE_DB_URL is empty in .env")

            def use_aaina_schema(conn):
                conn.execute(f'CREATE SCHEMA IF NOT EXISTS "{settings.db_schema}"')
                conn.execute(f'SET search_path TO "{settings.db_schema}"')
                conn.commit()

            _pool = ConnectionPool(
                settings.supabase_db_url, min_size=1, max_size=4, configure=use_aaina_schema,
                # dict_row: rows behave like dicts (row["name"]), same as SQLite below.
                # prepare_threshold=None: also works through Supabase's pooler.
                kwargs={"row_factory": dict_row, "prepare_threshold": None},
                open=True, timeout=15,
            )
    return _pool


@contextmanager
def connect():
    """
    Open the database for one short job:  with connect() as conn: conn.execute(...)
    Saves (commits) at the end, or undoes everything if an error happened.
    """
    if using_postgres():
        with _pg_pool().connection() as conn:
            yield _PgConn(conn)
        return
    os.makedirs(os.path.dirname(settings.db_path), exist_ok=True)
    conn = sqlite3.connect(settings.db_path)
    conn.row_factory = sqlite3.Row             # rows behave like dicts: row["name"]
    conn.execute("PRAGMA foreign_keys = ON")   # needed for ON DELETE CASCADE in SQLite
    try:
        with conn:                             # commit, or roll back on error
            yield conn
    finally:
        conn.close()


def init_db():
    """Create any missing tables (safe to run every start-up)."""
    with connect() as conn:
        if using_postgres():
            conn.execute(PG_SCHEMA)
            conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS event TEXT")
            # Supabase also lets browsers read tables through its REST API. Our tables are in
            # their own schema, which that API doesn't expose; row-level security with no
            # rules is a second lock. The backend's own login bypasses it.
            for table in ["users", "face_embeddings", "consents", "sessions",
                          "recognitions", "events", "app_state"]:
                conn.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
            return
        conn.executescript(SCHEMA)
        # Upgrade databases made before event mode existed: add the missing column.
        columns = [row["name"] for row in conn.execute("PRAGMA table_info(users)")]
        if "event" not in columns:
            conn.execute("ALTER TABLE users ADD COLUMN event TEXT")


def describe():
    """One line for the start-up message: which database is in use."""
    if using_postgres():
        host = settings.supabase_db_url.split("@")[-1].split("/")[0]   # never print the password
        return f"Supabase ({host}, schema {settings.db_schema})"
    return f"SQLite ({settings.db_path})"


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

def create_user(username, password_hash, profile, consent_version, event=None):
    user_id = str(uuid.uuid4())
    with connect() as conn:
        conn.execute(
            f"INSERT INTO users (id, username, password_hash, {', '.join(PROFILE_FIELDS)}, qr_token, event, created_at) "
            f"VALUES (?, ?, ?, {', '.join('?' for _ in PROFILE_FIELDS)}, ?, ?, ?)",
            [user_id, username, password_hash]
            + [_encode(f, profile.get(f)) for f in PROFILE_FIELDS]
            + [uuid.uuid4().hex, event, now()],
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
            "FROM users u WHERE LOWER(u.name) LIKE ? OR LOWER(u.username) LIKE ? ORDER BY u.created_at DESC",
            (f"%{search.lower()}%", f"%{search.lower()}%"),
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
        return conn.execute("SELECT COUNT(*) AS n FROM face_embeddings WHERE user_id = ?", (user_id,)).fetchone()["n"]


def load_visible_embeddings():
    """Return (user_ids list, matrix N x 512) for everyone who is not hidden."""
    with connect() as conn:
        rows = conn.execute(
            "SELECT e.user_id, e.embedding FROM face_embeddings e "
            "JOIN users u ON u.id = e.user_id WHERE u.visible = 1"
        ).fetchall()
    ids = [r["user_id"] for r in rows]
    matrix = np.array([np.frombuffer(bytes(r["embedding"]), dtype=np.float32) for r in rows]) if rows else np.zeros((0, 512), np.float32)
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
        # Every count query is written "SELECT COUNT(...) AS n ..." so both engines read row["n"].
        one = lambda sql, *a: conn.execute(sql, a).fetchone()["n"]  # noqa: E731
        recent = conn.execute(
            "SELECT r.at, u.name FROM recognitions r JOIN users u ON u.id = r.user_id "
            "ORDER BY r.at DESC LIMIT 20"
        ).fetchall()
        return {
            "users_total": one("SELECT COUNT(*) AS n FROM users"),
            "users_hidden": one("SELECT COUNT(*) AS n FROM users WHERE visible = 0"),
            "users_with_face": one("SELECT COUNT(DISTINCT user_id) AS n FROM face_embeddings"),
            "scans_last_10_min": one("SELECT COUNT(*) AS n FROM recognitions WHERE at >= ?", t - 600),
            "matches_today": one("SELECT COUNT(*) AS n FROM recognitions WHERE user_id IS NOT NULL AND at >= ?", start_of_day),
            "unknown_today": one("SELECT COUNT(*) AS n FROM recognitions WHERE user_id IS NULL AND at >= ?", start_of_day),
            "recent_matches": [{"name": r["name"], "at": r["at"]} for r in recent],
        }


# ---------- event mode (extra E) ----------

def get_current_event():
    """The event new sign-ups are tagged with, as a dict, or None."""
    with connect() as conn:
        row = conn.execute(
            "SELECT e.* FROM app_state s JOIN events e ON e.name = s.value WHERE s.key = 'current_event'"
        ).fetchone()
        return dict(row) if row else None


def start_event(name, delete_after):
    """Create the event (or update its delete date) and make it the current one."""
    with connect() as conn:
        conn.execute(
            "INSERT INTO events (name, delete_after, created_at) VALUES (?, ?, ?) "
            "ON CONFLICT(name) DO UPDATE SET delete_after = excluded.delete_after",
            (name, delete_after, now()),
        )
        conn.execute(
            "INSERT INTO app_state (key, value) VALUES ('current_event', ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (name,),
        )


def stop_event():
    """No current event: new sign-ups get no event tag (and are never auto-deleted)."""
    with connect() as conn:
        conn.execute("DELETE FROM app_state WHERE key = 'current_event'")


def list_events():
    with connect() as conn:
        rows = conn.execute(
            "SELECT e.*, (SELECT COUNT(*) FROM users u WHERE u.event = e.name) AS users "
            "FROM events e ORDER BY e.created_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]


def wipe_event(name):
    """Delete every user who signed up at this event, and the event itself. Returns how many users."""
    with connect() as conn:
        count = conn.execute("DELETE FROM users WHERE event = ?", (name,)).rowcount
        conn.execute("DELETE FROM events WHERE name = ?", (name,))
        conn.execute("DELETE FROM app_state WHERE key = 'current_event' AND value = ?", (name,))
        return count


def wipe_expired_events():
    """Auto-delete: wipe every event whose delete-after time has passed. Returns {event: users}."""
    with connect() as conn:
        names = [r["name"] for r in conn.execute(
            "SELECT name FROM events WHERE delete_after IS NOT NULL AND delete_after <= ?", (now(),))]
    return {name: wipe_event(name) for name in names}
