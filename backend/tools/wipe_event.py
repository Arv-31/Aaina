"""
wipe_event.py - event mode (extra E) from the command line. Run from the backend folder:

    .venv\\Scripts\\python tools\\wipe_event.py                  list events and their users
    .venv\\Scripts\\python tools\\wipe_event.py --expired        delete events past their date
    .venv\\Scripts\\python tools\\wipe_event.py --event "Expo"   delete everyone from one event

The server also runs the --expired check by itself at start-up and every hour.
Restart the server after wiping, so its in-memory face list is refreshed.
"""

import argparse
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import db  # noqa: E402


def show_events():
    events = db.list_events()
    current = db.get_current_event()
    if not events:
        print("No events yet. Start one from the admin console (PUT /admin/event).")
        return
    print(f"\n {'Event':30} {'Users':>5}  Auto-delete after")
    for e in events:
        when = datetime.fromtimestamp(e["delete_after"]).strftime("%Y-%m-%d %H:%M") if e["delete_after"] else "never"
        mark = "  (current)" if current and current["name"] == e["name"] else ""
        print(f" {e['name']:30} {e['users']:5}  {when}{mark}")
    print()


def main():
    parser = argparse.ArgumentParser(description="List or wipe Aaina events.")
    parser.add_argument("--event", help="name of the event to wipe")
    parser.add_argument("--expired", action="store_true", help="wipe events past their delete date")
    args = parser.parse_args()
    db.init_db()

    if args.expired:
        wiped = db.wipe_expired_events()
        print("Nothing has expired." if not wiped else
              "\n".join(f"Wiped '{name}': {count} user(s) deleted." for name, count in wiped.items()))
        return 0

    if args.event:
        if not any(e["name"] == args.event for e in db.list_events()):
            print(f"No event called '{args.event}'.")
            show_events()
            return 1
        typed = input(f"This deletes EVERY user from '{args.event}'. Type the event name to confirm: ")
        if typed != args.event:
            print("Names didn't match. Nothing was deleted.")
            return 1
        print(f"Wiped '{args.event}': {db.wipe_event(args.event)} user(s) deleted.")
        return 0

    show_events()
    return 0


if __name__ == "__main__":
    sys.exit(main())
