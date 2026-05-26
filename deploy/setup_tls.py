#!/usr/bin/env python3
"""Fix CRLF on shell scripts, sync .env, run issue-cert.sh and coturn install."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import paramiko

from remote_deploy import HOST, REMOTE_DIR, SSH_KEY, USER, upload_tree, run  # type: ignore[import-untyped]

DOMAIN = "lumin.tahseen.tech"
EMAIL = os.environ.get("CERTBOT_EMAIL", "raj.tahseen@gmail.com")


def patch_remote_env(sftp: paramiko.SFTPClient) -> None:
    path = f"{REMOTE_DIR}/.env"
    with sftp.open(path, "r") as f:
        content = f.read().decode("utf-8")
    lines = []
    for line in content.splitlines():
        if line.startswith("DOMAIN="):
            lines.append(f"DOMAIN={DOMAIN}")
        elif line.startswith("TURN_HOST="):
            lines.append(f"TURN_HOST={DOMAIN}")
        elif line.startswith("MEDIA_URL_SCHEME="):
            lines.append("MEDIA_URL_SCHEME=https")
        else:
            lines.append(line)
    with sftp.open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def get_turn_secret(sftp: paramiko.SFTPClient) -> str:
    with sftp.open(f"{REMOTE_DIR}/.env", "r") as f:
        for line in f.read().decode("utf-8").splitlines():
            if line.startswith("TURN_SECRET="):
                return line.split("=", 1)[1].strip()
    raise RuntimeError("TURN_SECRET not found in .env")


def main() -> None:
    local_root = Path(__file__).resolve().parents[1]
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {USER}@{HOST}...")
    ssh.connect(HOST, username=USER, key_filename=SSH_KEY, timeout=60)

    sftp = ssh.open_sftp()
    try:
        upload_tree(sftp, local_root, REMOTE_DIR)
        patch_remote_env(sftp)
        turn_secret = get_turn_secret(sftp)
    finally:
        sftp.close()

    run(ssh, "apt-get install -y -qq dos2unix", timeout=120)
    run(ssh, f'find {REMOTE_DIR} -name "*.sh" -exec dos2unix {{}} +', timeout=60)

    run(
        ssh,
        f"cd {REMOTE_DIR} && docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "up -d fastapi worker signaling nginx",
        timeout=300,
    )

    run(
        ssh,
        f"cd {REMOTE_DIR} && DOMAIN={DOMAIN} EMAIL={EMAIL} bash deploy/issue-cert.sh",
        timeout=600,
    )

    run(
        ssh,
        f"cd {REMOTE_DIR} && VPS_PUBLIC_IP={HOST} DOMAIN={DOMAIN} "
        f"TURN_SECRET={turn_secret} bash coturn/install.sh",
        timeout=300,
    )

    run(ssh, f"curl -fsSI https://{DOMAIN}/health | head -5", timeout=30)
    print(f"\nTLS live: https://{DOMAIN}/health")
    ssh.close()


if __name__ == "__main__":
    main()
