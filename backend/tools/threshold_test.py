"""
threshold_test.py - find the best "Unknown" cutoff using your own photos.

1. Put photos in backend/test_photos/, one folder per person:
       test_photos/
         aravind/   1.jpg 2.jpg 3.jpg 4.jpg
         rahul/     1.jpg 2.jpg
         sneha/     1.jpg 2.jpg 3.jpg
2. Run from the backend folder:
       .venv\\Scripts\\python tools\\threshold_test.py
       .venv\\Scripts\\python tools\\threshold_test.py --threshold 0.5   (check one value)

What it does:
  - Makes an embedding for every photo (photos are never copied or saved).
  - Scores every pair of photos.
      "same" pairs      = two photos of the same person -> should score HIGH
      "different" pairs = photos of two different people -> should score LOW
  - Shows, for many thresholds, how many pairs would be right or wrong.
  - Recommends a threshold that prefers showing "Unknown" over a wrong name.
  - Saves every pair score to results/pair_scores.csv (used later for the slide chart).
"""

import argparse
import csv
import itertools
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import face_engine  # noqa: E402

BACKEND_DIR = os.path.join(os.path.dirname(__file__), "..")
PHOTO_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".bmp")


def load_embeddings(photo_dir):
    """Return a list of (person, filename, embedding) for every usable photo."""
    items, skipped = [], []
    people = sorted(d for d in os.listdir(photo_dir) if os.path.isdir(os.path.join(photo_dir, d)))
    for person in people:
        folder = os.path.join(photo_dir, person)
        for name in sorted(os.listdir(folder)):
            if not name.lower().endswith(PHOTO_EXTS):
                continue
            emb, info = face_engine.embedding_from_file(os.path.join(folder, name))
            if emb is None:
                skipped.append(f"{person}/{name} ({info['reason']})")
            else:
                items.append((person, name, emb))
        print(f"  {person}: {sum(1 for p, _, _ in items if p == person)} usable photo(s)")
    return items, skipped


def score_pairs(items):
    """Score every pair. Returns a list of (kind, label_a, label_b, score)."""
    pairs = []
    for (pa, na, ea), (pb, nb, eb) in itertools.combinations(items, 2):
        kind = "same" if pa == pb else "different"
        pairs.append((kind, f"{pa}/{na}", f"{pb}/{nb}", face_engine.cosine_similarity(ea, eb)))
    return pairs


def counts_at(threshold, same, diff):
    """How many pairs each threshold gets right and wrong."""
    return {
        "correct_match": sum(s >= threshold for s in same),     # same person, said "match"
        "missed": sum(s < threshold for s in same),             # same person, said "Unknown"
        "correct_unknown": sum(s < threshold for s in diff),    # different people, said "Unknown"
        "wrong_match": sum(s >= threshold for s in diff),       # different people, said "match" (worst case)
    }


def recommend(same, diff):
    """
    Pick a cutoff. A wrong name on someone's face is worse than "Unknown",
    so we only accept thresholds with zero wrong matches on your photos.
    """
    if not same or not diff:
        return None, "Need at least 2 people and 2 photos of one person."
    highest_diff, lowest_same = max(diff), min(same)
    if lowest_same > highest_diff:
        # Clean gap: put the cutoff in the middle so there is room for error on both sides.
        t = round((lowest_same + highest_diff) / 2, 2)
        return t, (f"Clean gap: different people never scored above {highest_diff:.2f} and the same "
                   f"person never scored below {lowest_same:.2f}. The middle is {t:.2f}.")
    # Overlap: choose the smallest threshold with zero wrong matches, plus a small safety margin.
    t = round(highest_diff + 0.02, 2)
    c = counts_at(t, same, diff)
    return t, (f"Scores overlap. {t:.2f} gives zero wrong matches but misses {c['missed']} of "
               f"{len(same)} same-person pairs. Retake blurry or dark photos to improve this.")


def main():
    parser = argparse.ArgumentParser(description="Pick the face-match threshold from your own photos.")
    parser.add_argument("--photos", default=os.path.join(BACKEND_DIR, "test_photos"))
    parser.add_argument("--threshold", type=float, help="also report details for this one value")
    args = parser.parse_args()

    if not os.path.isdir(args.photos):
        print(f"Folder not found: {args.photos}")
        return 1

    print("\nReading photos...")
    items, skipped = load_embeddings(args.photos)
    for s in skipped:
        print(f"  skipped {s}")

    pairs = score_pairs(items)
    same = [s for k, _, _, s in pairs if k == "same"]
    diff = [s for k, _, _, s in pairs if k == "different"]
    if not same or not diff:
        print("\nNeed at least 2 people, and at least 2 photos of one person.")
        return 1

    print(f"\nSame-person pairs     : {len(same):3d}   lowest {min(same):.3f}   average {sum(same)/len(same):.3f}")
    print(f"Different-people pairs: {len(diff):3d}   highest {max(diff):.3f}   average {sum(diff)/len(diff):.3f}")

    # Table of thresholds from 0.20 to 0.75.
    print("\n Threshold | Correct match | Missed (Unknown) | Correct Unknown | WRONG match")
    print(" ----------+---------------+------------------+-----------------+------------")
    for i in range(20, 80, 5):
        t = i / 100
        c = counts_at(t, same, diff)
        flag = "  <- wrong names!" if c["wrong_match"] else ""
        print(f"   {t:.2f}    | {c['correct_match']:7d}       | {c['missed']:8d}         |"
              f" {c['correct_unknown']:8d}        | {c['wrong_match']:6d}{flag}")

    t, why = recommend(same, diff)
    print(f"\nRecommended threshold: {t:.2f}")
    print(f"  {why}")
    print(f"  Put it in backend/.env as  MATCH_THRESHOLD={t:.2f}")

    if args.threshold is not None:
        c = counts_at(args.threshold, same, diff)
        print(f"\nAt your threshold {args.threshold:.2f}: {c}")

    # Save every pair score (file names and numbers only, no images) for the threshold chart later.
    out_dir = os.path.join(BACKEND_DIR, "results")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "pair_scores.csv")
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["kind", "photo_a", "photo_b", "score"])
        for kind, a, b, s in sorted(pairs, key=lambda p: -p[3]):
            w.writerow([kind, a, b, f"{s:.4f}"])
    print(f"\nSaved all pair scores to {os.path.normpath(out_path)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
