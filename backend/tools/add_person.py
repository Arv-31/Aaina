"""
add_person.py - create a test account and enroll its face from a folder of photos.

The in-app signup arrives in Milestone 7. Until then, use this to put people in
the database so the phone has someone to recognise (Milestone 5 and 6 tests).
It talks to the RUNNING server, the same way the app will, so the server picks
up the new face straight away. Photos are only read and sent; nothing is copied.

Start the server first (python run.py), then in a second terminal:

    .venv\\Scripts\\python tools\\add_person.py --photos "test_photos\\me" ^
        --name "Aravind K" --linkedin "https://www.linkedin.com/in/aravind" ^
        --username aravind --password aainatest1

Optional card fields: --college, --course, --job, --company, --skills "Flutter, Python"
If the username already exists, it logs in and replaces that person's face.
"""

import argparse
import sys
from pathlib import Path

import httpx

PHOTO_TYPES = {".jpg", ".jpeg", ".png", ".webp"}


def main():
    p = argparse.ArgumentParser(description="Create a test account and enroll its face.")
    p.add_argument("--photos", required=True, help="folder with 3 to 5 photos of ONE person")
    p.add_argument("--name", required=True)
    p.add_argument("--linkedin", required=True, help="LinkedIn URL (required on every card)")
    p.add_argument("--username", required=True)
    p.add_argument("--password", required=True, help="at least 8 characters")
    p.add_argument("--server", default="http://localhost:8000")
    p.add_argument("--college"), p.add_argument("--course"), p.add_argument("--job")
    p.add_argument("--company"), p.add_argument("--skills", help='comma separated, e.g. "Flutter, Python"')
    args = p.parse_args()

    folder = Path(args.photos)
    photos = sorted(f for f in folder.iterdir() if f.suffix.lower() in PHOTO_TYPES) if folder.is_dir() else []
    if len(photos) < 3:
        sys.exit(f"Need at least 3 photos in {folder}, found {len(photos)}.")
    photos = photos[:5]  # the server accepts 3 to 5

    client = httpx.Client(base_url=args.server, timeout=60)
    try:
        client.get("/health").raise_for_status()
    except httpx.HTTPError:
        sys.exit(f"Can't reach the server at {args.server}. Start it with: python run.py")

    # 1. Sign up (or log in if this username already exists).
    profile = {"name": args.name, "linkedin_url": args.linkedin}
    optional = {"college": args.college, "course_year": args.course, "job_title": args.job, "company": args.company}
    profile.update({k: v for k, v in optional.items() if v})
    if args.skills:
        profile["skills"] = [s.strip() for s in args.skills.split(",") if s.strip()]

    r = client.post("/auth/signup", json={**profile, "username": args.username,
                                          "password": args.password, "consent": True})
    if r.status_code == 409:
        print("Username exists, logging in and replacing the face.")
        r = client.post("/auth/login", json={"username": args.username, "password": args.password})
    if r.status_code != 200:
        sys.exit(f"Account step failed ({r.status_code}): {r.text}")
    headers = {"Authorization": f"Bearer {r.json()['token']}"}
    # Existing account: also update the card with the details given this time.
    client.patch("/me", json=profile, headers=headers)

    # 2. Enroll the face photos.
    files = [("photos", (f.name, f.read_bytes(), "image/jpeg")) for f in photos]
    r = client.post("/enroll", files=files, headers=headers)
    if r.status_code != 200:
        sys.exit(f"Enroll failed ({r.status_code}): {r.text}")
    result = r.json()
    for photo in result.get("photos", []):
        mark = "ok " if photo["ok"] else "BAD"
        print(f"  {mark} {photos[photo['photo'] - 1].name}  {photo.get('hint') or ''}")
    if not result.get("enrolled"):
        sys.exit(f"Not enrolled: {result.get('message')}")
    print(f"\nDone: {args.name} enrolled with {result['faces_saved']} face(s).")
    print(f"Log in on the phone with username '{args.username}' and your password.")


if __name__ == "__main__":
    main()
