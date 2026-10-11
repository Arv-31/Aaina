"""
test_backend.py - automatic end-to-end test of the backend API (Milestones 2 and 3).

Run from the backend folder (the server does NOT need to be running):
    .venv\\Scripts\\python tools\\test_backend.py

It uses a temporary, throwaway database (your real data/aaina.db is never touched) and the
photos in test_photos/ (needs 2 people: one with 5+ photos, one with 3+). Photos are only read
into memory. It prints PASS/FAIL for each check and deletes the temporary database at the end.
"""

import os
import shutil
import sqlite3
import sys
import tempfile
import time
from datetime import datetime, timedelta

# Use a throwaway database and a test admin login BEFORE the app reads its settings.
TMP_DIR = tempfile.mkdtemp(prefix="aaina_test_")
os.environ["DB_PATH"] = os.path.join(TMP_DIR, "test.db")
import pyotp  # noqa: E402

TEST_SECRET = pyotp.random_base32()
os.environ["ADMIN_ID"] = "testadmin"
os.environ["ADMIN_TOTP_SECRET"] = TEST_SECRET
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.config import settings  # noqa: E402
from app.security import hash_password  # noqa: E402

# Settings were read on import above, so set the test admin password hash directly.
settings.admin_password_hash = hash_password("test-admin-password")

import warnings  # noqa: E402

warnings.filterwarnings("ignore", message=".*httpx.*")  # harmless notice from the test client
import cv2  # noqa: E402
import numpy as np  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import matcher  # noqa: E402
from app.main import app, run_auto_delete  # noqa: E402

PHOTOS = os.path.join(os.path.dirname(__file__), "..", "test_photos")
results = []


def check(name, ok, extra=""):
    results.append(ok)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{('  -> ' + str(extra)) if (extra and not ok) else ''}")


def load_people():
    people = {}
    for person in sorted(os.listdir(PHOTOS)):
        folder = os.path.join(PHOTOS, person)
        if os.path.isdir(folder):
            files = [os.path.join(folder, f) for f in sorted(os.listdir(folder))
                     if f.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))]
            people[person] = [open(f, "rb").read() for f in files]
    ranked = sorted(people.items(), key=lambda kv: -len(kv[1]))
    if len(ranked) < 2 or len(ranked[0][1]) < 5 or len(ranked[1][1]) < 3:
        sys.exit("Need test_photos/ with one person (5+ photos) and another (3+ photos).")
    return ranked[0], ranked[1]


def files(*photos):
    return [("photos", (f"p{i}.jpg", data, "image/jpeg")) for i, data in enumerate(photos)]


def one(photo):
    return {"photo": ("scan.jpg", photo, "image/jpeg")}


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def scan(client, token, photo):
    faces = client.post("/recognize", files=one(photo), headers=auth(token)).json()["faces"]
    return faces[0] if faces else {"status": "no_face"}


def main():
    (a_name, a_photos), (b_name, b_photos) = load_people()
    print(f"\nUsing '{a_name}' ({len(a_photos)} photos) and '{b_name}' ({len(b_photos)} photos)\n")

    with TestClient(app) as client:   # "with" runs the startup step (loads the model)
        print("Account")
        check("health is ok", client.get("/health").json()["ok"])
        alice = {"username": "alice@test.com", "password": "password123", "name": "Alice Test",
                 "linkedin_url": "linkedin.com/in/alice", "consent": True,
                 "college": "Test College", "github_url": "github.com/alice", "company": ""}
        r = client.post("/auth/signup", json={**alice, "consent": False})
        check("signup without consent is refused", r.status_code == 400, r.text)
        r = client.post("/auth/signup", json={**alice, "linkedin_url": "example.com/me"})
        check("signup with a non-LinkedIn link is refused", r.status_code == 422, r.text)
        r = client.post("/auth/signup", json=alice)
        check("signup works", r.status_code == 200, r.text)
        token_a = r.json()["token"]
        check("same username twice is refused", client.post("/auth/signup", json=alice).status_code == 409)
        r = client.post("/auth/login", json={"username": "ALICE@test.com", "password": "wrong-pass"})
        check("wrong password is refused", r.status_code == 401)
        r = client.post("/auth/login", json={"username": "ALICE@test.com", "password": "password123"})
        check("login works (username is not case-sensitive)", r.status_code == 200, r.text)
        check("scanning without login is refused", client.post("/recognize", files=one(a_photos[0])).status_code == 401)

        print("\nEnrollment quality check (extra C)")
        img = cv2.imdecode(np.frombuffer(a_photos[0], np.uint8), cv2.IMREAD_COLOR)
        blurred = cv2.imencode(".jpg", cv2.GaussianBlur(img, (0, 0), 6))[1].tobytes()
        dark = cv2.imencode(".jpg", (img * 0.2).astype(np.uint8))[1].tobytes()
        r = client.post("/enroll", files=files(blurred, dark, a_photos[0]), headers=auth(token_a)).json()
        problems = [p["problem"] for p in r["photos"]]
        check("blurry and dark photos are refused with hints", not r["enrolled"] and problems == ["blurry", "too_dark", None], problems)
        r = client.post("/enroll", files=files(a_photos[0], a_photos[1], b_photos[0]), headers=auth(token_a)).json()
        check("a photo of someone else in the set is caught", r.get("reason") == "mixed_people", r)
        check("only 2 photos is refused", client.post("/enroll", files=files(*a_photos[:2]), headers=auth(token_a)).status_code == 400)

        print("\nEnroll + recognize")
        r = client.post("/enroll", files=files(*a_photos[:3]), headers=auth(token_a)).json()
        check("enroll with 3 good photos works", r["enrolled"], r)
        for i, photo in enumerate(a_photos[3:], start=4):
            face = scan(client, token_a, photo)
            check(f"{a_name} photo {i} (not used to enroll) is recognized", face["status"] == "match" and face["card"]["name"] == "Alice Test", face)
        for i, photo in enumerate(b_photos, start=1):
            face = scan(client, token_a, photo)
            check(f"{b_name} photo {i} (not enrolled) shows Unknown", face["status"] == "unknown" and face["card"] is None, face)

        print("\nProfile card + sharing (extra B)")
        card = scan(client, token_a, a_photos[3])["card"]
        check("empty fields are left out of the card", "company" not in card and "instagram_url" not in card, card)
        check("links get https:// added", card.get("github_url") == "https://github.com/alice", card)
        client.patch("/me", json={"share": {"github_url": False}}, headers=auth(token_a))
        card = scan(client, token_a, a_photos[3])["card"]
        check("a field switched off is hidden from others", "github_url" not in card and card["college"] == "Test College", card)
        r = client.patch("/me", json={"linkedin_url": ""}, headers=auth(token_a))
        check("LinkedIn can't be removed", r.status_code == 422)

        print("\nQR fallback (extra A)")
        qr = client.get("/me", headers=auth(token_a)).json()["qr_value"]
        check("QR code shows the card", client.get(f"/qr/{qr}", headers=auth(token_a)).json().get("name") == "Alice Test")
        client.post("/me/qr/new", headers=auth(token_a))
        check("old QR stops working after making a new one", client.get(f"/qr/{qr}", headers=auth(token_a)).status_code == 404)

        print("\nHide me")
        client.patch("/me", json={"visible": False}, headers=auth(token_a))
        check("hidden user shows as Unknown", scan(client, token_a, a_photos[4])["status"] == "unknown")
        client.patch("/me", json={"visible": True}, headers=auth(token_a))
        check("un-hidden user is recognized again", scan(client, token_a, a_photos[4])["status"] == "match")

        print("\nShared phone (borrowed login + no double enrollment)")
        bob = {"username": "bob", "password": "password456", "name": "Bob Test",
               "linkedin_url": "https://www.linkedin.com/in/bob", "consent": True, "borrowed": True}
        token_b = client.post("/auth/signup", json=bob).json()["token"]
        r = client.post("/enroll", files=files(*a_photos[:3]), headers=auth(token_b)).json()
        check("enrolling someone else's already-registered face is refused", r.get("reason") == "already_enrolled", r)
        r = client.post("/enroll", files=files(*b_photos[:3]), headers=auth(token_b)).json()
        check(f"{b_name} can enroll on a borrowed login", r["enrolled"], r)
        conn = sqlite3.connect(os.environ["DB_PATH"])
        conn.execute("UPDATE sessions SET last_used = ? WHERE user_id = (SELECT id FROM users WHERE username='bob')",
                     (int(time.time()) - 11 * 60,))
        conn.commit()
        conn.close()
        check("borrowed login expires after 10 idle minutes", client.get("/me", headers=auth(token_b)).status_code == 401)

        print("\nAdmin")
        r = client.post("/admin/login", json={"admin_id": "testadmin", "password": "test-admin-password", "otp": "000000"})
        check("admin login with a wrong code is refused", r.status_code == 401)
        r = client.post("/admin/login", json={"admin_id": "testadmin", "password": "test-admin-password",
                                              "otp": pyotp.TOTP(TEST_SECRET).now()})
        check("admin login with ID + password + code works", r.status_code == 200, r.text)
        admin = auth(r.json()["token"])
        check("users can't open admin pages", client.get("/admin/overview", headers=auth(token_a)).status_code == 401)
        ov = client.get("/admin/overview", headers=admin).json()
        check("overview counts users and scans", ov["users_total"] == 2 and ov["users_with_face"] == 2 and ov["matches_today"] > 0, ov)
        users = client.get("/admin/users", params={"q": "bob"}, headers=admin).json()
        check("admin can search users", len(users) == 1 and users[0]["name"] == "Bob Test", users)
        check("admin (kiosk) can scan", scan(client, r.json()["token"], a_photos[3])["status"] == "match")

        print("\nDelete my data")
        alice_id = client.get("/me", headers=auth(token_a)).json()["user_id"]
        check("delete works", client.delete("/me", headers=auth(token_a)).json()["deleted"])
        check("login is gone after delete", client.get("/me", headers=auth(token_a)).status_code == 401)
        token_c = client.post("/auth/signup", json={**bob, "username": "carol", "borrowed": False}).json()["token"]
        check("deleted user's face now shows Unknown", scan(client, token_c, a_photos[3])["status"] == "unknown")
        conn = sqlite3.connect(os.environ["DB_PATH"])
        left = sum(conn.execute(f"SELECT COUNT(*) FROM {t} WHERE user_id = ?", (alice_id,)).fetchone()[0]
                   for t in ["face_embeddings", "consents", "sessions", "recognitions"])
        conn.close()
        check("no rows about the deleted user remain in any table", left == 0, left)
        stored = [f for f in os.listdir(TMP_DIR) if not f.startswith("test.db")]
        check("no photo files were saved anywhere", stored == [], stored)

    # Milestone 3: "restart" the server. The in-memory face list is emptied, so anything that
    # still works afterwards must have come back from the database file.
    matcher._user_ids, matcher._matrix = [], np.zeros((0, 512), np.float32)
    with TestClient(app) as client:
        print("\nAfter a server restart")
        check("login from before the restart still works", client.get("/me", headers=auth(token_c)).status_code == 200)
        face = scan(client, token_c, b_photos[0])
        check(f"{b_name} is still recognized (faces reloaded from the database)",
              face["status"] == "match" and face["card"]["name"] == "Bob Test", face)

        print("\nEvent mode (extra E)")
        r = client.post("/admin/login", json={"admin_id": "testadmin", "password": "test-admin-password",
                                              "otp": pyotp.TOTP(TEST_SECRET).now()})
        admin = auth(r.json()["token"])
        check("no event running yet", client.get("/event").json() is None)
        r = client.put("/admin/event", json={"name": "Old Expo", "delete_after_date": "2020-01-01"}, headers=admin)
        check("a delete date in the past is refused", r.status_code == 400)
        tomorrow = (datetime.now().date() + timedelta(days=1)).isoformat()
        r = client.put("/admin/event", json={"name": "Test Expo", "delete_after_date": tomorrow}, headers=admin)
        check("admin can start an event with a delete date", r.status_code == 200 and r.json()["delete_after_date"] == tomorrow, r.text)
        check("the app can read the event and its delete date", client.get("/event").json()["name"] == "Test Expo")
        client.post("/auth/signup", json={**bob, "username": "dave", "name": "Dave Expo", "borrowed": False})
        users = {u["name"]: u for u in client.get("/admin/users", headers=admin).json()}
        check("new sign-ups are tagged with the event", users["Dave Expo"]["event"] == "Test Expo" and users["Bob Test"]["event"] is None, users)
        r = client.delete("/admin/events/Test Expo", params={"confirm": "wrong"}, headers=admin)
        check("wipe needs the event name typed again", r.status_code == 400)

        # Pretend the delete date has passed, then run the hourly auto-delete check.
        conn = sqlite3.connect(os.environ["DB_PATH"])
        conn.execute("UPDATE events SET delete_after = ? WHERE name = 'Test Expo'", (int(time.time()) - 1,))
        conn.commit()
        conn.close()
        wiped = run_auto_delete()
        names = [u["name"] for u in client.get("/admin/users", headers=admin).json()]
        check("auto-delete removes the event's users after the date", wiped == {"Test Expo": 1} and "Dave Expo" not in names, wiped)
        check("users without an event are kept", "Bob Test" in names, names)
        check("the expired event is no longer current", client.get("/event").json() is None)

        client.put("/admin/event", json={"name": "Second Expo"}, headers=admin)
        client.post("/auth/signup", json={**bob, "username": "erin", "name": "Erin Expo", "borrowed": False})
        r = client.delete("/admin/events/Second Expo", params={"confirm": "Second Expo"}, headers=admin)
        check("one-click wipe deletes everyone from an event", r.json().get("users_deleted") == 1, r.text)
        events = client.get("/admin/events", headers=admin).json()
        check("wiped events disappear from the list", events == [], events)

    shutil.rmtree(TMP_DIR, ignore_errors=True)
    passed = sum(results)
    print(f"\n{passed} of {len(results)} checks passed.\n")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
