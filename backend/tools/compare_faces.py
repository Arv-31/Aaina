"""
compare_faces.py - compare two photos and say if they are the same person.

Run from the backend folder:
    .venv\\Scripts\\python tools\\compare_faces.py photo1.jpg photo2.jpg
    .venv\\Scripts\\python tools\\compare_faces.py photo1.jpg photo2.jpg --threshold 0.5
"""

import argparse
import os
import sys

# Let this script import the "app" package that lives one folder up.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import face_engine  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description="Compare two face photos.")
    parser.add_argument("photo_a")
    parser.add_argument("photo_b")
    parser.add_argument("--threshold", type=float, default=face_engine.MATCH_THRESHOLD,
                        help=f"cutoff score (default {face_engine.MATCH_THRESHOLD})")
    args = parser.parse_args()

    emb_a, info_a = face_engine.embedding_from_file(args.photo_a)
    emb_b, info_b = face_engine.embedding_from_file(args.photo_b)

    # Explain clearly if a photo had no usable face.
    for name, emb, info in [(args.photo_a, emb_a, info_a), (args.photo_b, emb_b, info_b)]:
        if emb is None:
            print(f"No usable face in {name} ({info['reason']}).")
            return 1

    score = face_engine.cosine_similarity(emb_a, emb_b)
    same = face_engine.is_match(score, args.threshold)

    print()
    print(f"  Similarity score : {score:.3f}")
    print(f"  Threshold        : {args.threshold:.2f}")
    print(f"  Result           : {'SAME PERSON' if same else 'Unknown / different person'}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
