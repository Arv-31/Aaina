"""
face_engine.py - everything Aaina does with faces, in one place.

What it does:
  1. Loads the free, open-source InsightFace model (runs on this laptop's CPU, no internet
     needed after the first download).
  2. Turns a photo into an "embedding": a list of 512 numbers that describes a face.
  3. Compares two embeddings with cosine similarity (1.0 = identical, 0 = unrelated).

Privacy rule: this file never saves images. Photos are read into memory, turned into
numbers, and then thrown away when the function returns.

Milestone 1 uses this from the scripts in backend/tools/. Milestone 2 (the FastAPI server)
will import the same functions, so nothing here is throwaway code.
"""

import os

import cv2
import numpy as np
from dotenv import load_dotenv

load_dotenv()  # reads backend/.env if it exists (settings only, never secrets in code)

# "buffalo_s" = small and fast (~0.13 s per face on an i3 laptop). Default.
# "buffalo_l" = a bit more accurate but ~10x slower on CPU.
# Embeddings from the two models do NOT match each other: switching means everyone re-enrolls.
MODEL_NAME = os.getenv("FACE_MODEL", "buffalo_s")

# Score at or above this = same person. Below = "Unknown".
# 0.38 was picked with tools/threshold_test.py (see docs/DECISIONS.md). Override in .env.
MATCH_THRESHOLD = float(os.getenv("MATCH_THRESHOLD", "0.38"))

# Faces smaller than this many pixels wide are too blurry to trust.
MIN_FACE_SIZE = int(os.getenv("MIN_FACE_SIZE", "60"))

_model = None  # loaded once, then reused (loading takes a few seconds)


def get_model():
    """Load InsightFace the first time it's needed, then keep it in memory."""
    global _model
    if _model is None:
        # Imported here so other files can import face_engine without paying the load cost.
        from insightface.app import FaceAnalysis

        print(f"[face_engine] Loading InsightFace model '{MODEL_NAME}' (first run downloads it once: ~120 MB small, ~280 MB large)...")
        # The model pack also has landmark and age/gender models we don't need.
        # Loading only detection + recognition makes it several times faster.
        _model = FaceAnalysis(
            name=MODEL_NAME,
            providers=["CPUExecutionProvider"],
            allowed_modules=["detection", "recognition"],
        )
        # ctx_id=-1 means CPU. det_size is the size the detector looks at; 640 is the default.
        _model.prepare(ctx_id=-1, det_size=(640, 640))
        print("[face_engine] Model ready.")
    return _model


def read_image(path):
    """Read an image file into memory as a BGR array (OpenCV's format)."""
    # np.fromfile + imdecode works with Windows paths that contain spaces or non-English letters.
    data = np.fromfile(path, dtype=np.uint8)
    img = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"Could not read image: {path}")
    return img


def normalize(vec):
    """Scale a vector to length 1, so a plain dot product equals cosine similarity."""
    vec = np.asarray(vec, dtype=np.float32)
    return vec / (np.linalg.norm(vec) + 1e-10)


def get_embedding(img):
    """
    Find the biggest face in an image and return (embedding, info).

    embedding: 512 numbers, normalized to length 1, or None if no usable face.
    info:      a small dict explaining what happened (useful for error messages).
    """
    faces = get_model().get(img)
    if not faces:
        return None, {"reason": "no_face"}

    # If there are several faces, use the biggest one (closest to the camera).
    def area(f):
        x1, y1, x2, y2 = f.bbox
        return (x2 - x1) * (y2 - y1)

    face = max(faces, key=area)
    x1, y1, x2, y2 = face.bbox
    width = int(x2 - x1)
    if width < MIN_FACE_SIZE:
        return None, {"reason": "face_too_small", "face_width": width}

    return normalize(face.embedding), {
        "reason": "ok",
        "faces_found": len(faces),
        "face_width": width,
        "detector_score": round(float(face.det_score), 3),
    }


def embedding_from_file(path):
    """Convenience: read a photo, embed it, and let the image go out of memory."""
    img = read_image(path)
    emb, info = get_embedding(img)
    del img  # the photo is discarded here; only numbers are kept
    return emb, info


def cosine_similarity(a, b):
    """Both vectors are already length 1, so the dot product IS the cosine similarity."""
    return float(np.dot(a, b))


def is_match(score, threshold=None):
    """True if the score is high enough to say 'same person'."""
    return score >= (MATCH_THRESHOLD if threshold is None else threshold)
