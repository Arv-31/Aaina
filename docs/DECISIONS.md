# Aaina: decisions on top of the synopsis

The synopsis (`SociaLink_Project_Synopsis.pdf`, the project's old working name) is the
source of truth. These are the changes and choices made since. Useful for judge questions.

| Topic | Decision | Why |
|---|---|---|
| Name | Aaina, tagline "See who you're meeting." | Final project name |
| Face detection on phone | Google ML Kit | Free, on-device, official Flutter plugin, gives tracking IDs and head angles |
| Database | SQLite by default, Supabase switchable in `.env` | Works fully offline at the expo; cloud option kept |
| Liveness | Head-turn at enrollment (ML Kit head angles) | Stops enrolling a printed photo; reuses the left/right shots |
| Platforms | Android app + Web app (no iOS) | iOS builds need a Mac. Web covers laptops and desktops |
| Logins | Separate user login and admin login | Admin console is for organisers only |
| Profile data | Smart form + optional LinkedIn PDF import | LinkedIn pages cannot be fetched for free or legally |
| Profile AI | Rule-based PDF reader first, then a local Ollama model (Qwen2.5 1.5B) fills gaps in the background | Rule #2 updated: no cloud AI; a local, offline model may read profile text. Face recognition stays InsightFace |
| Empty fields | Hidden on the card, never "not found". Minimum card = name + LinkedIn | Cleaner card |
| Design | Dark only, accent #5B8CFF, Bricolage Grotesque titles, Geist body, mirrored-"a" logo | Approved preview v2 |
| Face model | InsightFace `buffalo_s`, only detection + recognition loaded. `buffalo_l` switchable in `.env` | Measured on the i3 laptop: 0.13 s per face vs 1.36 s for `buffalo_l`. Live recognition needs speed. Switching model means re-enrolling everyone |

## Where the extras go

| Extra | Milestone |
|---|---|
| A. QR fallback | M2 (token + QR) and M6 (scan button) |
| B. Per-field sharing | M2 (backend filters fields) and M8 (toggles) |
| C. Enrollment quality check | M2 (backend checks) and M7 (hints in the app) |
| D. Save contact (vCard) | M6 (expanded card) |
| E. Event mode + auto-delete | M3 (event tag, delete-after date, wipe script) |
| F. Live dashboard | After the core flow (becomes the admin console) |
| G. Accuracy test + table | After the core flow |
| H. Threshold chart | After the core flow, uses `backend/results/pair_scores.csv` |
| I. Mirror mode (front camera shows your own card) | M6 |

## Threshold

Chosen value: **0.38** (model `buffalo_s`, tested 2026-10-11)

How it was chosen: `tools/threshold_test.py` on 11 photos of 2 people (31 same-person pairs,
24 different-people pairs).
- Different people: highest 0.122, average 0.048
- Same person: lowest 0.409, average 0.601
- The script recommended 0.27 (middle of the clean gap). We picked 0.38 instead: it still
  gets all 31 same-person pairs right, and leaves more margin against strangers, because at
  the expo there will be many more people than in the test. Rule: "Unknown" is better than a
  wrong name.
- Checked against strangers: 200 people (511 photos) from LFW, a free public research face
  dataset, plus the developer's photos. Results at 0.38:
  - 135,527 different-people pairs: **0 wrong matches** (closest strangers scored 0.314)
  - The developer's photos vs all 200 strangers: highest 0.215
  - 454 same-person pairs: 2.6% fall below 0.38 and show "Unknown". Fine in the app, because
    each person enrolls several shots and the camera checks many frames.
  - At 0.27 (the first suggestion) there were 20 wrong matches, so the higher value was right.
- Re-run with more people before the expo if possible; raw scores are in
  `backend/results/pair_scores.csv` (gitignored, used later for the threshold chart).
