#!/usr/bin/env python3
"""Sync project to VPS and rebuild/restart the fastapi service only."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import paramiko

# Reuse upload helpers from remote_deploy
from remote_deploy import HOST, REMOTE_DIR, SSH_KEY, USER, upload_tree, run  # type: ignore[import-untyped]


def main() -> None:
    local_root = Path(__file__).resolve().parents[1]
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {USER}@{HOST}...")
    ssh.connect(HOST, username=USER, key_filename=SSH_KEY, timeout=60)

    print("Uploading project files to", REMOTE_DIR, "...")
    sftp = ssh.open_sftp()
    try:
        upload_tree(sftp, local_root, REMOTE_DIR)
    finally:
        sftp.close()

    run(
        ssh,
        f"cd {REMOTE_DIR} && "
        "docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "up -d --build fastapi",
        timeout=900,
    )

    run(
        ssh,
        f"curl -fsS 'http://127.0.0.1/health?format=full' | head -c 200; echo",
        timeout=30,
    )
    print(f"\nDone. HTML dashboard: http://{HOST}/health")
    print(f"Lightweight probe:   http://{HOST}/health")
    print(f"Full JSON report:    http://{HOST}/health?format=full")
    ssh.close()


if __name__ == "__main__":
    main()
