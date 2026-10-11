# Aaina: context for Claude Code

Read `docs/SociaLink_Project_Synopsis.pdf` (source of truth; "SociaLink" was the old name)
and `docs/DECISIONS.md` (everything agreed since) before doing any work.

## What it is
Aaina (tagline "See who you're meeting.") recognizes opted-in people through the camera and
shows their profile card next to their face. College expo project. The developer is
early-intermediate: write simple, commented code and explain as you go.

## Hard rules
1. Free tools only. No paid services or anything needing a credit card.
2. No cloud AI or chatbot in the running app. Face recognition = local InsightFace.
   Exception agreed by the developer: a local, offline Ollama model (Qwen2.5 1.5B) may parse
   LinkedIn PDF / pasted profile text in the background. Rule-based parser runs first.
3. Never store face photos. Embeddings only; discard images right after processing.
4. No secrets in the Flutter app or Git. Use `.env` + `.env.example`; `.env` is gitignored.
5. Consent, hide-me and delete-my-data are required.
6. All colors/fonts/spacing in one theme file. UI widgets have no network/DB code.
   Profile cards take a simple data object.
7. Backend starts with one command; the app's server address lives in one config file.
8. Out of scope: messaging, feeds, likes, followers.

## How to work
- One milestone at a time (synopsis section 10). After each: how to run and test it, files
  created and what each does, then STOP and wait for "next".
- The developer prefers that you pick the best free, fast option yourself and state the choice
  in a line, instead of long question forms. Show a visual preview before building UI.
- Flag anything too hard for the expo timeline before building it.

## Design (locked)
Dark only. Accent #5B8CFF, Bricolage Grotesque titles, Geist body, Geist Mono for data.
Logo: two lowercase "a" bowls mirrored around one shared accent bar, plus the wordmark "aaina"
with the "i" in the accent color. No Hindi text. Subtle animated dot-field background.
User login (Android app): form plus playful mirror character (eyes follow the text being typed and close
on the password field). Web is admin-only. Admin login is a separate page (ID + password + one-time code) with a
live overview panel. Reference: `docs/design/aaina-design-preview.html` (open in a browser).

## Profile card rules
Fields: name, LinkedIn (both required at signup); student status, college, course/year, job
title, company, skills, GitHub, Instagram, portfolio (optional). Empty fields are hidden,
never shown as "not found". Minimum card = name + LinkedIn. Form input beats AI-parsed values.
LinkedIn pages cannot be fetched or scraped; data comes only from the form, an uploaded
LinkedIn "Save to PDF" file, or pasted text.

## Status (update this as milestones finish)
- Milestone 1 (face matching script): DONE 2026-10-11. `backend/app/face_engine.py`,
  `backend/tools/compare_faces.py`, `backend/tools/threshold_test.py`.
  Model = buffalo_s, only detection + recognition loaded (~0.13 s per face on the i3 laptop;
  buffalo_l was 1.36 s). Threshold = 0.38 (details in `docs/DECISIONS.md`).
- Milestone 2 next: FastAPI backend with /enroll, /recognize, user accounts and separate admin
  login, plus extras A, B, C (see DECISIONS.md).

## Setting up a new machine (Windows)
1. Python 3.11 (python.org, tick "Add to PATH"). Newer versions may lack InsightFace support.
2. Microsoft C++ Build Tools, "Desktop development with C++" (InsightFace compiles a C part).
3. In `backend/`: `python -m venv .venv`, `.venv\Scripts\activate`,
   `pip install -r requirements.txt`, `copy .env.example .env`.
4. Flutter SDK + Android Studio are needed from Milestone 4.
