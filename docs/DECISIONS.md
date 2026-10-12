# Aaina: decisions on top of the synopsis

The synopsis (`SociaLink_Project_Synopsis.pdf`, the project's old working name) is the
source of truth. These are the changes and choices made since. Useful for judge questions.

| Topic | Decision | Why |
|---|---|---|
| Name | Aaina, tagline "See who you're meeting." | Final project name |
| Face detection on phone | Google ML Kit | Free, on-device, official Flutter plugin, gives tracking IDs and head angles |
| Database | SQLite (default), Supabase switchable in `.env` | Works offline at the expo, no internet needed |
| Moving to the expo laptop | USB stick: `tools/usb.py save` on this laptop, `tools/usb.py load` on the expo laptop. Carries the database, `.env` (same admin login) and the face model (no download needed). Old files are kept as `.before-usb-` copies | This laptop will NOT be at the expo. SQLite is one file, so a stick is the simplest way to carry it. Uses SQLite's own backup feature, so the copy is safe even while the server runs |
| Supabase switch | `DB_BACKEND=supabase` + the "Session pooler" connection string. Same SQL for both engines; tables live in a private `aaina` schema with row-level security on. Switching doesn't copy data | Supabase is plain Postgres, so one driver (psycopg, free) is enough; no Supabase key in the app. The private schema keeps tables away from Supabase's public REST API. Optional; free Supabase projects pause after a week unused |
| Liveness | Head-turn at enrollment (ML Kit head angles) | Stops enrolling a printed photo; reuses the left/right shots |
| Platforms | Android app = everything for users (signup, face enrollment, profile, privacy, scanning others). Web = admin-only console. One Flutter codebase, no iOS | Decided 2026-10-11. Phone camera + ML Kit gives the smooth live demo. Phone browsers block the camera on plain-HTTP LAN pages, so users stay in the app. iOS builds need a Mac. Keep a demo phone at the stall for visitors without Android |
| Logins | User login in the Android app. Admin login (ID + password + one-time code) only on the web console | Admin console is for organisers only |
| No phone of your own | Accounts belong to the person (email/username + password), never to a device. Any phone with the app can: "Add someone else" (sign up + face scan + card, then back to the owner's account; the guest's login is never saved), and log in with a "Borrowed phone" switch (forgotten on close or after 10 min idle). Admin can delete data at the stall after a password or live-face check | Visitors without Android can still join; the stall's demo phone uses the same flow |
| Admin web console | Live overview, user management (hide/remove, delete requests), event mode + wipe, accuracy page (threshold chart), big-screen kiosk mode (laptop webcam shows enrolled visitors' cards) | Admin-exclusive features; kiosk works because a laptop browser may use its own camera on localhost |
| Profile data | Smart form + optional LinkedIn PDF import | LinkedIn pages cannot be fetched for free or legally |
| Profile AI | Rule-based PDF reader first, then a local Ollama model (Qwen2.5 1.5B) fills gaps in the background | Rule #2 updated: no cloud AI; a local, offline model may read profile text. Face recognition stays InsightFace |
| Empty fields | Hidden on the card, never "not found". Minimum card = name + LinkedIn | Cleaner card |
| Design | Dark only, accent #5B8CFF, Bricolage Grotesque titles, Geist body, mirrored-"a" logo | Approved preview v2 |
| Face model | InsightFace `buffalo_s`, only detection + recognition loaded. `buffalo_l` switchable in `.env` | Measured on the i3 laptop: 0.13 s per face vs 1.36 s for `buffalo_l`. Live recognition needs speed. Switching model means re-enrolling everyone |
| Detector size | `DET_SIZE=320` (was 640) | At 640 a tight 256 px phone-style face crop was not detected at all; at 320 it is, and scans are faster (crop 0.26 s, full photo 0.41 s). Recognition accuracy unchanged: still 0 wrong matches in 136k LFW stranger pairs at 0.38 |
| App-to-server security | No shared "API key" in the app. Every scan/edit needs a login token (`Authorization: Bearer`). DB stores only a SHA-256 hash of each token; passwords stored as salted PBKDF2 hashes | A key inside an APK can be extracted, so it isn't a secret (rule 4). Tokens are per person and can be revoked |
| Admin one-time code | TOTP from a free authenticator app (Google/Microsoft Authenticator), set up with `tools/setup_admin.py` | Free, works offline at the expo. SMS/email codes cost money or need internet |
| Unknown faces in the log | Admin overview counts scans. An "Unknown" scan stores only the time, nothing about the face | Keeps the promise "Unknown means nothing is stored" while the dashboard still shows activity |
| Camera screen (M4) | Portrait only, `ResolutionPreset.medium` (~640x480), NV21 frames to ML Kit, busy frames dropped. Microphone permission removed from the APK | Simple camera-to-screen math; small frames keep ML Kit fast on mid-range phones. Aaina never records audio, so it doesn't ask for it |
| Fonts | Bricolage Grotesque, Geist, Geist Mono bundled as files in the app (SIL OFL licence) | The google_fonts package downloads fonts at runtime, which fails offline at the expo |
| Phone testing without USB debugging | Build the APK on the laptop and copy it to the phone's Download folder over USB (file transfer), then tap to install | The Galaxy J7 Pro test phone would not offer ADB. Copying the APK always works. M4 tested this way 2026-10-12: boxes follow faces on both cameras, ML Kit 100-250 ms |
| Camera screen look (M5) | AR heads-up style (preview v2, `docs/design/m5-recognition-preview.html`): lock-on brackets with tick marks, dot-mesh + spinning ring while checking, glass card beside the face joined by a leader line, "In view" strip, faint HUD grid + lens corners. The card on the camera shows ONLY name, current status (student: course/year + college; professional: job title + company) and LinkedIn. No skills, no "future" lines, no match score | Developer: "too simple, want advanced" and "just current status and LinkedIn" (2026-10-12). Full card details stay for the expanded card (M6) |
| Profile cards (M6) | Camera card: "VERIFIED · AAINA" header, initials in a turning accent ring, status with a cap/briefcase icon, LinkedIn, HUD corner ticks; it unfolds out of the leader line with a light sweep (repeats every 6 s). 2+ people = compact cards, placed so they never overlap or cover another face. Tap = "Aaina ID" sheet: animated banner, status, skills, link tiles, Save contact. QR mode on the same camera (ML Kit barcode scanning) + "Show my code" (qr_flutter). Mirror mode = front camera recognises you: "YOU" tag, visible/hidden + how many details you share. Save contact = flutter_contacts opens the phone's own new-contact screen | Developer: "most presentable profile card, the impression comes from design" (2026-10-12). All free, offline, no new permissions; no new backend routes |
| Sign-up on the laptop | Visitors can sign up on the STALL laptop (the one running the server) in its browser, using its webcam, as well as in the Android app. Same Flutter code. Other laptops can't: browsers block the camera on plain-http network pages, and HTTPS certificates are too fragile for the expo | Developer asked 2026-10-12 ("users may sign up through laptop or mobile"). Replaces the earlier "web = admin only" for this one flow. Laptop layout: webcam view + "In view" side list + "Sign up on this laptop" button (screens in M7) |
| Testing before M7 | `backend/tools/add_person.py` creates an account and enrolls a face from a photo folder; the app has a Connect sheet (server address + username + password). The server address typed there is saved on the phone and overrides `config.dart` | No signup screens until M7; the expo laptop has a different IP, and rebuilding the APK for that is slow without USB debugging |
| "Social" scope | Aaina stays an AR social card app. The only extra is the thumbs-up animation. No songs, no status line, no daily notification, no feeds, likes, followers or messaging | Decided 2026-10-12 (songs, open-palm hide and status of the day were proposed and dropped by the developer) |
| Thumbs-up animation (extra J) | When a recognised person shows a thumbs-up, their personal animation plays around their face and card on the scanner's phone (about 1.5 s, card pops and glows in their colour). Matched to the nearest face. One at a time per face, short cooldown so it doesn't loop | Decided 2026-10-12. Hand detection = MediaPipe Gesture Recognizer (free, on-device, has "Thumb_Up"), via a small Kotlin bridge (no official Flutter plugin). Runs only while a known card is on screen, every few frames, to stay fast on old phones. Risky part: prototype on the J7 Pro first |
| How the animation is personal | Users only see "Pick your vibe" with a row of emojis (+ Skip). Secretly each emoji is a theme: motion, shapes and palette (e.g. ⚡ electric arcs, 🔥 ember sparks, 🚀 launch streaks + shockwave, 🎧 equaliser bars + pulse rings, 💻 glitch / RGB split / pixel blocks, 🎯 HUD lock-on rings, 🧠 node network). The app never mentions themes. Then the profile adds unique elements so two people with the same emoji differ: name hash = seed for angles, timing, particle count and colour shift; skills = 1-2 mono-font glyphs in the effect (e.g. </>, UI, ML); student = course/year stamp, job = company initials; GitHub link = contribution-grid pixels; ends with their initials monogram. Only fields the person shares are used. Skip = emoji chosen from their skills/role | Decided 2026-10-12. Drawn in Flutter (CustomPainter), no packages, no files, no sound, offline |
| Animation tone | Sharp, fast, bold, high contrast: shockwaves, arcs, streaks, glitch, HUD rings, geometric shards. Never soft or cutesy: no hearts, flowers, bubbles, pastel sparkles. No 🌸-type emojis in the picker | Developer's request 2026-10-12 |

## Where the extras go

| Extra | Milestone |
|---|---|
| A. QR fallback | M2 (token + QR) and M6 (scan button) |
| B. Per-field sharing | M2 (backend filters fields) and M8 (toggles) |
| C. Enrollment quality check | M2 (backend checks) and M7 (hints in the app) |
| D. Save contact (vCard) | M6 (expanded card) |
| E. Event mode + auto-delete | M3 (event tag, delete-after date, wipe script) |
| F. Live dashboard | After the core flow (becomes the admin web console; kiosk mode last) |
| G. Accuracy test + table | After the core flow |
| H. Threshold chart | After the core flow, uses `backend/results/pair_scores.csv` |
| I. Mirror mode (front camera shows your own card) | M6 |
| J. Personal thumbs-up animation | New milestone 6b, right after the cards (gesture prototype on the J7 Pro first; preview of the themes before building). "Pick your vibe" screen goes into M7 signup and M8 profile |

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
