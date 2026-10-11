"""
setup_admin.py - create (or change) the admin login. Run once, from the backend folder:

    .venv\\Scripts\\python tools\\setup_admin.py

It asks for an admin ID and password, then shows a QR code. Scan it with a free
authenticator app (Google Authenticator or Microsoft Authenticator). That app then shows
the 6-digit one-time code you type on the admin login page.

What it writes to backend/.env (never committed to Git):
  ADMIN_ID, ADMIN_PASSWORD_HASH (not the password itself), ADMIN_TOTP_SECRET
Restart the server afterwards.
"""

import getpass
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pyotp  # noqa: E402
import qrcode  # noqa: E402

from app.config import BACKEND_DIR  # noqa: E402
from app.security import hash_password  # noqa: E402

ENV_PATH = os.path.join(BACKEND_DIR, ".env")


def set_env_values(values):
    """Replace or add KEY=value lines in .env, keeping everything else as it was."""
    lines = open(ENV_PATH, encoding="utf-8").read().splitlines() if os.path.exists(ENV_PATH) else []
    for key, value in values.items():
        new_line = f"{key}={value}"
        for i, line in enumerate(lines):
            if line.startswith(f"{key}="):
                lines[i] = new_line
                break
        else:
            lines.append(new_line)
    with open(ENV_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    admin_id = input("Admin ID (e.g. admin): ").strip()
    if len(admin_id) < 3:
        print("Admin ID must be at least 3 characters.")
        return 1
    password = getpass.getpass("Admin password (min 10 characters, typing is hidden): ")
    if len(password) < 10:
        print("Password too short.")
        return 1
    if getpass.getpass("Type it again: ") != password:
        print("Passwords don't match.")
        return 1

    secret = pyotp.random_base32()
    set_env_values({
        "ADMIN_ID": admin_id,
        "ADMIN_PASSWORD_HASH": hash_password(password),
        "ADMIN_TOTP_SECRET": secret,
    })

    uri = pyotp.TOTP(secret).provisioning_uri(name=admin_id, issuer_name="Aaina Admin")
    print("\nScan this with Google Authenticator / Microsoft Authenticator:\n")
    qr = qrcode.QRCode(border=2)
    qr.add_data(uri)
    qr.print_ascii(invert=True)
    print(f"\nCan't scan? In the app choose 'Enter a setup key' and type: {secret}")
    print("\nSaved to backend/.env. Restart the server, then log in at POST /admin/login.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
