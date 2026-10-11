# Aaina backend

FastAPI + InsightFace, runs on the laptop. The phone app and the admin web console talk to it.

## Start it (one command)

```
cd backend
.venv\Scripts\python run.py
```

Open http://localhost:8000/docs to try every route in the browser.
The phone uses the "From the phone" address that `run.py` prints.

## First-time setup

See "Setting up a new machine" in the main `CLAUDE.md`, then:

```
copy .env.example .env
.venv\Scripts\python tools\setup_admin.py     (admin ID, password, authenticator QR)
```

## Tests

```
.venv\Scripts\python tools\test_backend.py      full API test, throwaway database
.venv\Scripts\python tools\threshold_test.py    pick the match threshold from test_photos/
.venv\Scripts\python tools\compare_faces.py a.jpg b.jpg
```

## Files

| File | What it does |
|---|---|
| `app/main.py` | All API routes |
| `app/config.py` | Reads every setting from `.env` |
| `app/db.py` | All database code (SQLite) |
| `app/security.py` | Password hashes, login tokens, admin one-time code |
| `app/face_engine.py` | InsightFace: find faces, make embeddings, compare |
| `app/matcher.py` | In-memory matrix of enrolled faces, finds the best match |
| `app/quality.py` | Enrollment photo checks and hints (extra C) |
| `app/models.py` | Request formats and the profile card builder |
| `run.py` | Starts the server |
