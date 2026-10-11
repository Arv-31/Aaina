"""
quality.py - enrollment quality check (extra C).

Before saving anyone's face we check every photo, and give a short hint the app can show:
  - exactly one face in the photo
  - face big enough (not too far from the camera)
  - not too dark / too bright
  - not blurry (sharpness measured with OpenCV's Laplacian)
Then we check the set of photos:
  - all photos are the SAME person (stops mixing in someone else's photo)
  - this face isn't already enrolled on a different account
"""

import cv2
import numpy as np

from app import face_engine, matcher
from app.config import settings

HINTS = {
    "unreadable": "This file isn't a photo we can read. Try again.",
    "no_face": "No face found. Look straight at the camera.",
    "many_faces": "More than one face in the photo. Only you should be in the frame.",
    "too_small": "Face is too far away. Move the phone closer.",
    "blurry": "Photo is blurry. Hold the phone steady.",
    "too_dark": "Too dark. Move to a brighter spot.",
    "too_bright": "Too bright. Avoid strong light behind or on your face.",
}


def _face_crop_gray(img, box):
    x1, y1, x2, y2 = box
    h, w = img.shape[:2]
    crop = img[max(0, y1):min(h, y2), max(0, x1):min(w, x2)]
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    # Resize to a fixed width so the blur score means the same thing for every photo size.
    return cv2.resize(gray, (112, int(112 * gray.shape[0] / max(gray.shape[1], 1)) or 112))


def check_photo(data):
    """Check one uploaded photo. Returns (embedding or None, problem code or None, details)."""
    img = face_engine.decode_image(data)
    if img is None:
        return None, "unreadable", {}
    faces = face_engine.get_all_faces(img)
    if not faces:
        return None, "no_face", {}
    # Ignore tiny background faces; complain only if 2+ real faces are in the frame.
    big = [f for f in faces if f["width"] >= face_engine.MIN_FACE_SIZE]
    if len(big) > 1:
        return None, "many_faces", {"faces": len(big)}
    face = max(faces, key=lambda f: f["width"])
    details = {"face_width": face["width"], "detector_score": face["detector_score"]}
    if face["width"] < face_engine.MIN_FACE_SIZE:
        return None, "too_small", details

    gray = _face_crop_gray(img, face["box"])
    del img  # the photo is discarded here; only numbers are kept
    sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    brightness = float(np.mean(gray))
    details.update(sharpness=round(sharpness, 1), brightness=round(brightness, 1))
    # Brightness first: a dark photo also looks "blurry", and "too dark" is the useful hint.
    if brightness < settings.brightness_min:
        return None, "too_dark", details
    if brightness > settings.brightness_max:
        return None, "too_bright", details
    if sharpness < settings.blur_min:
        return None, "blurry", details
    return face["embedding"], None, details


def check_set(embeddings, user_id):
    """
    Check the good photos together. Returns a problem code or None.
    'mixed_people'  = one photo looks like a different person than the others
    'already_enrolled' = this face belongs to another account
    """
    # Compare each photo with the average of the OTHER photos. A side-turned head scores a bit
    # lower than a straight one, so this uses a gentler bar than the recognition threshold.
    for i, emb in enumerate(embeddings):
        others = face_engine.normalize(np.mean([e for j, e in enumerate(embeddings) if j != i], axis=0))
        if face_engine.cosine_similarity(emb, others) < settings.same_set_min:
            return "mixed_people"
    for emb in embeddings:
        other, _ = matcher.best_match(emb)
        if other is not None and other != user_id:
            return "already_enrolled"
    return None


SET_HINTS = {
    "mixed_people": "These photos don't all look like the same person. Retake them, only you in front of the camera.",
    "already_enrolled": "This face is already registered to another account. Log in to that account instead.",
}
