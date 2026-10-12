"""
run.py - start the Aaina backend with one command (from the backend folder):

    .venv\\Scripts\\python run.py

Then open http://localhost:8000/docs on this laptop.
The phone uses this laptop's IP address instead of localhost (printed below).
"""

import socket

import uvicorn

from app.config import settings


def lan_ip():
    """Best guess at this laptop's address on the hotspot/Wi-Fi (no data is sent anywhere)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    print(f"\n  Aaina backend starting...")
    ip = lan_ip()
    print(f"  API docs        : http://localhost:{settings.port}/docs")
    print(f"  Laptop app      : http://localhost:{settings.port}/app/")
    print(f"  Phone app (APK) : http://{ip}:{settings.port}/get-app")
    print(f"  Phone server    : http://{ip}:{settings.port}  (type this in the app's Connect sheet)\n")
    uvicorn.run("app.main:app", host=settings.host, port=settings.port)
