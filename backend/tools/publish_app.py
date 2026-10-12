"""
publish_app.py - put the latest app builds where the server can hand them out.

Build the app first (in the app folder):
    flutter build web --base-href /app/
    flutter build apk --release

Then, in the backend folder:
    .venv\Scripts\python tools\publish_app.py

It copies:
    app/build/web                         -> backend/public/app   (laptop browser version)
    app/build/.../flutter-apk/app-release.apk -> backend/public/Aaina.apk (phone download)

Restart the server afterwards. Links:
    Stall laptop : http://localhost:8000/app/
    Phones       : http://<laptop-ip>:8000/get-app   (run.py prints the IP)
"""

import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # the Aaina folder
WEB = ROOT / "app" / "build" / "web"
APK = ROOT / "app" / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
PUBLIC = ROOT / "backend" / "public"


def main():
    PUBLIC.mkdir(exist_ok=True)
    done = 0
    if WEB.exists():
        shutil.rmtree(PUBLIC / "app", ignore_errors=True)
        shutil.copytree(WEB, PUBLIC / "app")
        print(f"  Laptop app  -> {PUBLIC / 'app'}")
        done += 1
    else:
        print("  No web build found. Run: flutter build web --base-href /app/")
    if APK.exists():
        shutil.copy2(APK, PUBLIC / "Aaina.apk")
        size = APK.stat().st_size / 1e6
        print(f"  Android APK -> {PUBLIC / 'Aaina.apk'} ({size:.0f} MB)")
        done += 1
    else:
        print("  No APK found. Run: flutter build apk --release")
    if done:
        print("\n  Restart the server (python run.py) to pick up the changes.")
    sys.exit(0 if done else 1)


if __name__ == "__main__":
    main()
