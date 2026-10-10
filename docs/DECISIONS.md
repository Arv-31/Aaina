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

Chosen value: _fill in after running `tools/threshold_test.py`_
How it was chosen: _paste the recommendation line here_
