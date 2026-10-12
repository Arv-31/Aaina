"""
main.py - the Aaina API (FastAPI). Start it with:  .venv\\Scripts\\python run.py
Then open http://localhost:8000/docs to try every route in the browser.

Who can call what:
  anyone          GET /health, POST /auth/signup, POST /auth/login
  logged-in user  /me (view, edit, hide, delete-my-data), /enroll, /recognize, /qr/{code}
  this laptop     POST /detect (face boxes only, for the laptop-webcam camera screen)
  admin           /admin/... (ID + password + one-time code; web console only)
The app sends its login token in the header:  Authorization: Bearer <token>
"""

import asyncio
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import Depends, FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles

from app import db, face_engine, matcher, quality, security
from app.config import settings
from app.models import (CONSENT_VERSION, AdminLoginIn, AdminUserUpdate, EventIn, LoginIn,
                        ProfileUpdate, SignupIn, build_card)


def run_auto_delete():
    """Event mode (extra E): wipe events whose delete-after date has passed."""
    wiped = db.wipe_expired_events()
    if wiped:
        matcher.reload()
        for name, count in wiped.items():
            print(f"[aaina] Auto-delete: event '{name}' passed its date, removed {count} user(s).")
    return wiped


async def auto_delete_loop():
    """Check once an hour while the server runs (also catches up right after a restart)."""
    while True:
        await asyncio.sleep(3600)
        run_auto_delete()


@asynccontextmanager
async def lifespan(app):
    """Runs once when the server starts: set up the database and load the face model."""
    db.init_db()
    run_auto_delete()        # an event may have expired while the server was off
    matcher.reload()
    face_engine.get_model()  # load now so the first scan isn't slow
    event = db.get_current_event()
    print(f"[aaina] Database: {db.describe()}")
    print(f"[aaina] Ready. {matcher.count()} face embeddings loaded. "
          f"Event: {event['name'] if event else 'none'}. "
          f"Admin login {'ON' if security.admin_configured() else 'OFF (run tools/setup_admin.py)'}.")
    task = asyncio.create_task(auto_delete_loop())
    yield
    task.cancel()


app = FastAPI(title="Aaina API", version="0.2", description="See who you're meeting.", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                   allow_methods=["*"], allow_headers=["*"])

bearer = HTTPBearer(auto_error=False)  # adds the "Authorize" button on /docs


# ---------- who is calling? ----------

def _token(creds):
    if creds is None:
        raise HTTPException(401, "Please log in.")
    return creds.credentials


def current_user(creds: HTTPAuthorizationCredentials = Depends(bearer)):
    """Use in a route to require a logged-in user. Returns the user dict."""
    user_id = security.user_from_token(_token(creds))
    user = db.get_user(user_id) if user_id else None
    if user is None:
        raise HTTPException(401, "Login expired. Please log in again.")
    return user


def current_admin(creds: HTTPAuthorizationCredentials = Depends(bearer)):
    if not security.is_admin_token(_token(creds)):
        raise HTTPException(401, "Admin login required.")
    return True


def user_or_admin(creds: HTTPAuthorizationCredentials = Depends(bearer)):
    """Scanning is allowed for logged-in users and for the admin (kiosk mode)."""
    token = _token(creds)
    if security.is_admin_token(token) or security.user_from_token(token):
        return True
    raise HTTPException(401, "Please log in.")


async def _read_photo(upload: UploadFile):
    data = await upload.read()
    if len(data) > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(413, f"Photo is bigger than {settings.max_upload_mb} MB.")
    return data


def _my_profile(user):
    """Everything about me, for my own settings screen."""
    profile = {k: user[k] for k in db.PROFILE_FIELDS}
    profile.update(
        user_id=user["id"], username=user["username"], visible=user["visible"],
        share={f: user["share"].get(f, True) for f in db.SHAREABLE_FIELDS},
        face_enrolled=db.count_embeddings(user["id"]) > 0,
        qr_value=f"aaina:{user['qr_token']}",
        card_preview=build_card(user),
    )
    return profile


def _event_info(event):
    """Event dict for the app, e.g. the consent screen shows the auto-delete date."""
    if event is None:
        return None
    when = event["delete_after"]
    return {"name": event["name"], "delete_after": when,
            "delete_after_date": (datetime.fromtimestamp(when) - timedelta(days=1)).date().isoformat() if when else None}


# ---------- public ----------

@app.get("/health", tags=["public"])
def health():
    return {"ok": True, "model": face_engine.MODEL_NAME, "threshold": face_engine.MATCH_THRESHOLD,
            "faces_loaded": matcher.count()}


@app.get("/event", tags=["public"])
def current_event():
    """The event running now (or null). The consent screen shows when data is auto-deleted."""
    return _event_info(db.get_current_event())


@app.post("/auth/signup", tags=["account"])
def signup(body: SignupIn):
    """Create an account + profile. The user must have accepted the consent screen."""
    if not body.consent:
        raise HTTPException(400, "You must accept the consent screen to sign up.")
    if db.get_user_by_username(body.username):
        raise HTTPException(409, "That username is already taken.")
    profile = body.model_dump(exclude={"username", "password", "consent", "borrowed"})
    event = db.get_current_event()
    user_id = db.create_user(body.username, security.hash_password(body.password), profile, CONSENT_VERSION,
                             event["name"] if event else None)
    token = security.new_user_session(user_id, body.borrowed)
    return {"user_id": user_id, "token": token, "borrowed": body.borrowed,
            "next": "Send 3 to 5 face photos to POST /enroll"}


@app.post("/auth/login", tags=["account"])
def login(body: LoginIn):
    """Log in on any phone. borrowed=true = forget me after a few idle minutes."""
    key = f"user:{body.username}"
    if security.too_many_failures(key):
        raise HTTPException(429, "Too many wrong tries. Wait 5 minutes.")
    user = db.get_user_by_username(body.username)
    if user is None or not security.check_password(body.password, user["password_hash"]):
        security.record_failure(key)
        raise HTTPException(401, "Wrong username or password.")
    security.clear_failures(key)
    return {"user_id": user["id"], "token": security.new_user_session(user["id"], body.borrowed),
            "borrowed": body.borrowed}


@app.post("/auth/logout", tags=["account"])
def logout(creds: HTTPAuthorizationCredentials = Depends(bearer)):
    security.end_user_session(_token(creds))
    return {"ok": True}


# ---------- my profile ----------

@app.get("/me", tags=["my profile"])
def get_me(user=Depends(current_user)):
    return _my_profile(user)


@app.patch("/me", tags=["my profile"])
def update_me(body: ProfileUpdate, user=Depends(current_user)):
    """Edit fields, hide me (visible=false), or switch single card fields off (share)."""
    changes = body.model_dump(exclude_unset=True)   # only the fields that were sent
    if "share" in changes:
        changes["share"] = {**user["share"], **changes["share"]}
    db.update_user(user["id"], changes)
    if "visible" in changes:
        matcher.reload()  # hidden people drop out of recognition straight away
    return _my_profile(db.get_user(user["id"]))


@app.delete("/me", tags=["my profile"])
def delete_me(user=Depends(current_user)):
    """Delete my data: profile, face embeddings, consent record and logins. Cannot be undone."""
    db.delete_user(user["id"])
    matcher.reload()
    return {"deleted": True}


@app.post("/me/qr/new", tags=["my profile"])
def new_qr(user=Depends(current_user)):
    """Make a new QR code. The old one stops working (e.g. if a screenshot was shared)."""
    db.update_user(user["id"], {"qr_token": uuid.uuid4().hex})
    return {"qr_value": f"aaina:{db.get_user(user['id'])['qr_token']}"}


@app.post("/enroll", tags=["my profile"])
async def enroll(photos: list[UploadFile] = File(..., description="3 to 5 face photos"),
                 user=Depends(current_user)):
    """
    Save my face (or replace it). Each photo is checked (extra C); bad ones come back with a hint.
    Photos are read in memory and thrown away. Only the 512-number embeddings are stored.
    """
    if not settings.enroll_min_photos <= len(photos) <= settings.enroll_max_photos:
        raise HTTPException(400, f"Send {settings.enroll_min_photos} to {settings.enroll_max_photos} photos.")

    results, good = [], []
    for i, upload in enumerate(photos):
        emb, problem, details = quality.check_photo(await _read_photo(upload))
        results.append({"photo": i + 1, "ok": problem is None, "problem": problem,
                        "hint": quality.HINTS.get(problem), **details})
        if emb is not None:
            good.append(emb)

    if len(good) < settings.enroll_min_photos:
        return {"enrolled": False, "reason": "photo_quality",
                "message": f"Need {settings.enroll_min_photos} good photos, got {len(good)}. See the hints.",
                "photos": results}

    problem = quality.check_set(good, user["id"])
    if problem:
        return {"enrolled": False, "reason": problem, "message": quality.SET_HINTS[problem], "photos": results}

    db.replace_embeddings(user["id"], good)
    matcher.reload()
    return {"enrolled": True, "faces_saved": len(good), "photos": results}


# ---------- scanning ----------

@app.post("/recognize", tags=["scan"])
async def recognize(photo: UploadFile = File(..., description="A face crop or a camera frame"),
                    _=Depends(user_or_admin)):
    """
    Find every face in the photo and say who it is, or "unknown".
    Unknown faces are not stored anywhere: only the time of the scan is counted.
    """
    img = face_engine.decode_image(await _read_photo(photo))
    if img is None:
        raise HTTPException(400, "Couldn't read that image.")
    height, width = img.shape[:2]
    faces = face_engine.get_all_faces(img)
    del img  # the photo is discarded here

    results = []
    for face in faces:
        if face["width"] < face_engine.MIN_FACE_SIZE:
            results.append({"box": face["box"], "status": "too_small", "card": None})
            continue
        user_id, score = matcher.best_match(face["embedding"])
        user = db.get_user(user_id) if user_id else None
        db.log_recognition(user["id"] if user else None)
        if user and user["visible"]:
            results.append({"box": face["box"], "status": "match", "score": round(score, 3),
                            "card": build_card(user)})
        else:
            results.append({"box": face["box"], "status": "unknown", "card": None})
    return {"image_size": [width, height], "faces": results}


@app.post("/detect", tags=["scan"])
async def detect(request: Request,
                 photo: UploadFile = File(..., description="A camera frame from the laptop webcam")):
    """
    Face boxes only: no names, no matching, nothing stored or logged.
    Used when the camera screen runs in a browser on this laptop (the phone app
    finds faces itself with ML Kit). Only accepted from this laptop itself.
    """
    if request.client is None or request.client.host not in ("127.0.0.1", "::1", "localhost"):
        raise HTTPException(403, "Face boxes are only available on the server laptop itself.")
    img = face_engine.decode_image(await _read_photo(photo))
    if img is None:
        raise HTTPException(400, "Couldn't read that image.")
    height, width = img.shape[:2]
    boxes = face_engine.detect_boxes(img)
    del img  # the photo is discarded here
    return {"image_size": [width, height], "boxes": boxes}


@app.get("/qr/{code}", tags=["scan"])
def qr_lookup(code: str, _=Depends(user_or_admin)):
    """QR fallback (extra A): scan someone's QR code (aaina:xxxx) to see their card."""
    user = db.get_user_by_qr(code.removeprefix("aaina:"))
    if user is None or not user["visible"]:
        raise HTTPException(404, "No profile for this code.")
    return build_card(user)


# ---------- admin (web console) ----------

@app.post("/admin/login", tags=["admin"])
def admin_login(body: AdminLoginIn):
    if not security.admin_configured():
        raise HTTPException(503, "Admin login is not set up. Run tools/setup_admin.py.")
    if security.too_many_failures("admin"):
        raise HTTPException(429, "Too many wrong tries. Wait 5 minutes.")
    if not security.check_admin_login(body.admin_id, body.password, body.otp):
        security.record_failure("admin")
        raise HTTPException(401, "Wrong admin ID, password or code.")
    security.clear_failures("admin")
    return {"token": security.new_admin_session(), "hours": settings.admin_session_hours}


@app.post("/admin/logout", tags=["admin"])
def admin_logout(creds: HTTPAuthorizationCredentials = Depends(bearer)):
    security.end_admin_session(_token(creds))
    return {"ok": True}


@app.get("/admin/overview", tags=["admin"])
def admin_overview(_=Depends(current_admin)):
    return {**db.overview(), "faces_loaded": matcher.count(), "threshold": face_engine.MATCH_THRESHOLD,
            "event": _event_info(db.get_current_event())}


@app.get("/admin/users", tags=["admin"])
def admin_users(q: str = Query("", description="search name or username"), _=Depends(current_admin)):
    return [{"user_id": u["id"], "username": u["username"], "name": u["name"], "visible": u["visible"],
             "face_count": u["face_count"], "event": u["event"], "created_at": u["created_at"]}
            for u in db.list_users(q)]


@app.patch("/admin/users/{user_id}", tags=["admin"])
def admin_update_user(user_id: str, body: AdminUserUpdate, _=Depends(current_admin)):
    """Hide or un-hide someone (e.g. after a complaint)."""
    if db.get_user(user_id) is None:
        raise HTTPException(404, "No such user.")
    db.update_user(user_id, {"visible": body.visible})
    matcher.reload()
    return {"user_id": user_id, "visible": body.visible}


@app.delete("/admin/users/{user_id}", tags=["admin"])
def admin_delete_user(user_id: str, _=Depends(current_admin)):
    """Delete someone's data at their request (check their password or face first, at the stall)."""
    if not db.delete_user(user_id):
        raise HTTPException(404, "No such user.")
    matcher.reload()
    return {"deleted": True}


# ---------- admin: event mode (extra E) ----------

@app.get("/admin/events", tags=["admin"])
def admin_events(_=Depends(current_admin)):
    current = db.get_current_event()
    return [{**_event_info(e), "users": e["users"], "current": bool(current and current["name"] == e["name"])}
            for e in db.list_events()]


@app.put("/admin/event", tags=["admin"])
def admin_start_event(body: EventIn, _=Depends(current_admin)):
    """Start an event (or change its delete date). New sign-ups get tagged with it."""
    delete_after = None
    if body.delete_after_date:
        if body.delete_after_date < datetime.now().date():
            raise HTTPException(400, "The delete date can't be in the past.")
        # Delete at the END of that day (midnight, laptop's local time).
        midnight = datetime.combine(body.delete_after_date + timedelta(days=1), datetime.min.time())
        delete_after = int(midnight.timestamp())
    db.start_event(body.name, delete_after)
    return _event_info(db.get_current_event())


@app.post("/admin/event/stop", tags=["admin"])
def admin_stop_event(_=Depends(current_admin)):
    """Stop tagging new sign-ups. Existing event users keep their delete date."""
    db.stop_event()
    return {"current_event": None}


@app.delete("/admin/events/{name}", tags=["admin"])
def admin_wipe_event(name: str, confirm: str = Query(..., description="Type the event name again"),
                     _=Depends(current_admin)):
    """One-click wipe: delete everyone who signed up at this event. Cannot be undone."""
    if confirm != name:
        raise HTTPException(400, "Type the exact event name in 'confirm' to wipe it.")
    if not any(e["name"] == name for e in db.list_events()):
        raise HTTPException(404, "No such event.")
    count = db.wipe_event(name)
    matcher.reload()
    return {"event": name, "users_deleted": count}


# ---------- the app itself: laptop browser version + APK download ----------
# tools/publish_app.py copies the Flutter builds into backend/public/:
#   public/app/      -> http://localhost:8000/app/   (stall laptop, uses its webcam)
#   public/Aaina.apk -> http://<laptop-ip>:8000/get-app (phones install over Wi-Fi)
PUBLIC = Path(__file__).resolve().parent.parent / "public"


@app.get("/", include_in_schema=False)
def home():
    """Opening the server address in a browser goes straight to the app."""
    return RedirectResponse("/app/" if (PUBLIC / "app").exists() else "/docs")


@app.get("/get-app", tags=["public"])
def get_app():
    """Download the Android app (APK) from this laptop. No account needed."""
    apk = PUBLIC / "Aaina.apk"
    if not apk.exists():
        raise HTTPException(404, "No APK published yet. Run tools/publish_app.py on the laptop.")
    return FileResponse(apk, filename="Aaina.apk", media_type="application/vnd.android.package-archive")


if (PUBLIC / "app").exists():
    app.mount("/app", StaticFiles(directory=PUBLIC / "app", html=True), name="web-app")
