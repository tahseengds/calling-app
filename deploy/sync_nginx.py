#!/usr/bin/env python3
"""Upload nginx config and reload nginx — no image rebuild required."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import paramiko

from remote_deploy import HOST, REMOTE_DIR, SSH_KEY, USER, run  # type: ignore[import-untyped]

# Files to upload: (local path relative to project root, remote path relative to REMOTE_DIR)
NGINX_FILES = [
    "nginx/conf.d/lumin.conf",
]


def main() -> None:
    local_root = Path(__file__).resolve().parents[1]
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {USER}@{HOST}...")
    ssh.connect(HOST, username=USER, key_filename=SSH_KEY, timeout=60)

    sftp = ssh.open_sftp()
    try:
        for rel in NGINX_FILES:
            local = local_root / rel
            remote = f"{REMOTE_DIR}/{rel}"
            # Ensure remote directory exists
            remote_dir = remote.rsplit("/", 1)[0]
            try:
                sftp.stat(remote_dir)
            except OSError:
                sftp.mkdir(remote_dir)
            print(f"  Uploading {rel} ...")
            sftp.put(str(local), remote)
    finally:
        sftp.close()

    # Test nginx config before reloading — catches syntax errors before they break the site
    run(
        ssh,
        f"cd {REMOTE_DIR} && "
        "docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "exec -T nginx nginx -t",
        timeout=30,
    )

    run(
        ssh,
        f"cd {REMOTE_DIR} && "
        "docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "exec -T nginx nginx -s reload",
        timeout=30,
    )

    run(ssh, "curl -fsS http://127.0.0.1/health; echo", timeout=15)
    print(f"\nNginx reloaded. Media signing now routes to /api/media/verify-signature.")
    ssh.close()


if __name__ == "__main__":
    main()
