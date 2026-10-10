# Aaina

**See who you're meeting.**

Aaina recognizes people who have opted in through the camera and shows their profile card
next to their face. Face recognition runs on a laptop with the open-source InsightFace model.
Only face embeddings (numbers) are stored, never photos. Users can hide themselves or delete
all their data at any time.

Built for a college expo. Everything uses free tools.

## Project layout

```
aaina/
  backend/            Python: face engine now, FastAPI server from Milestone 2
    app/face_engine.py   load InsightFace, make embeddings, compare faces
    tools/               command-line scripts (compare two photos, pick the threshold)
    test_photos/         your private test photos (ignored by Git)
    requirements.txt
    .env.example         copy to .env for local settings
  app/                Flutter app (Android + Web), from Milestone 4
  docs/               project synopsis and decisions
```

## Milestone 1: face matching

```powershell
cd backend
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env

# Compare two photos
python tools\compare_faces.py path\to\a.jpg path\to\b.jpg

# Pick the "Unknown" threshold from your own photos (see test_photos/README.md)
python tools\threshold_test.py
```

## Status

- [x] Milestone 1: face matching script and threshold test
- [ ] Milestone 2: FastAPI backend (enroll, recognize, user + admin login)
- [ ] Milestones 3 to 10: see `docs/DECISIONS.md`
