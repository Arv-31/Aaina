"""
matcher.py - finds who a face belongs to.

All visible users' embeddings sit in one NumPy matrix in memory (synopsis section 5).
Matching one face = one matrix multiplication = microseconds, even with hundreds of photos.
The matrix is rebuilt whenever someone enrolls, hides, unhides or deletes their data.
"""

import threading

import numpy as np

from app import db, face_engine

_lock = threading.Lock()
_user_ids = []
_matrix = np.zeros((0, 512), np.float32)


def reload():
    """Re-read every visible embedding from the database."""
    global _user_ids, _matrix
    ids, matrix = db.load_visible_embeddings()
    with _lock:
        _user_ids, _matrix = ids, matrix


def best_match(embedding):
    """
    Return (user_id, score) for the closest enrolled face.
    user_id is None when nobody scores at or above the threshold ("Unknown").
    """
    with _lock:
        ids, matrix = _user_ids, _matrix
    if len(ids) == 0:
        return None, 0.0
    scores = matrix @ embedding            # cosine similarity with every stored face
    best = int(np.argmax(scores))
    score = float(scores[best])
    if face_engine.is_match(score):
        return ids[best], score
    return None, score


def count():
    return len(_user_ids)
