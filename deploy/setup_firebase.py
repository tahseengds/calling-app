#!/usr/bin/env python3
"""
Upload Firebase service account JSON and configure FCM on the VPS.

Usage:
  set DEPLOY_PASSWORD=...
  python deploy/setup_firebase.py path/to/firebase-service-account.json

Reads project_id from the JSON and updates .env on the server.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import paramiko

from remote_deploy import HOST, REMOTE_DIR, USER, run  # type: ignore[import-untyped]

PASSWORD = os.environ["DEPLOY_PASSWORD"]
REMOTE_JSON = f"{REMOTE_DIR}/firebase-service-account.json"
CONTAINER_PATH = "/app/firebase-service-account.json"


def patch_env(content: str, project_id: str) -> str:
    lines: list[str] = []
    seen_pid = False
    seen_path = False
    for line in content.splitlines():
        if line.startswith("FIREBASE_PROJECT_ID="):
            lines.append(f"FIREBASE_PROJECT_ID={project_id}")
            seen_pid = True
        elif line.startswith("FIREBASE_SERVICE_ACCOUNT_PATH="):
            lines.append(f"FIREBASE_SERVICE_ACCOUNT_PATH={CONTAINER_PATH}")
            seen_path = True
        else:
            lines.append(line)
    if not seen_pid:
        lines.append(f"FIREBASE_PROJECT_ID={project_id}")
    if not seen_path:
        lines.append(f"FIREBASE_SERVICE_ACCOUNT_PATH={CONTAINER_PATH}")
    return "\n".join(lines) + "\n"


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python deploy/setup_firebase.py <firebase-service-account.json>")
        sys.exit(1)

    local_json = Path(sys.argv[1]).resolve()
    if not local_json.is_file():
        print(f"File not found: {local_json}", file=sys.stderr)
        sys.exit(1)

    data = json.loads(local_json.read_text(encoding="utf-8"))
    project_id = data.get("project_id")
    if not project_id:
        print("JSON missing project_id", file=sys.stderr)
        sys.exit(1)

    local_root = Path(__file__).resolve().parents[1]
    local_env = local_root / ".env"
    if local_env.is_file():
        local_env.write_text(
            patch_env(local_env.read_text(encoding="utf-8"), project_id),
            encoding="utf-8",
        )
        print(f"Updated local {local_env}")

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {USER}@{HOST}...")
    ssh.connect(HOST, username=USER, password=PASSWORD, timeout=60)

    sftp = ssh.open_sftp()
    sftp.put(str(local_json), REMOTE_JSON)
    prod_compose = local_root / "docker-compose.prod.yml"
    if prod_compose.is_file():
        sftp.put(str(prod_compose), f"{REMOTE_DIR}/docker-compose.prod.yml")
        print(f"Uploaded {prod_compose.name}")
    with sftp.open(f"{REMOTE_DIR}/.env", "r") as f:
        remote_env = f.read().decode("utf-8")
    with sftp.open(f"{REMOTE_DIR}/.env", "w") as f:
        f.write(patch_env(remote_env, project_id))
    sftp.close()

    run(ssh, f"chmod 600 {REMOTE_JSON}")
    # Recreate so new volume mounts from docker-compose.prod.yml are applied.
    run(
        ssh,
        f"cd {REMOTE_DIR} && docker compose -f docker-compose.yml "
        f"-f docker-compose.prod.yml up -d --force-recreate fastapi worker",
        timeout=300,
    )
    run(
        ssh,
        f"docker exec lumin-fastapi-1 test -f {CONTAINER_PATH}",
        timeout=30,
    )

    run(
        ssh,
        f"docker exec lumin-fastapi-1 python -c \""
        f"from google.oauth2 import service_account; "
        f"c=service_account.Credentials.from_service_account_file("
        f"'{CONTAINER_PATH}', scopes=['https://www.googleapis.com/auth/firebase.messaging']); "
        f"print('FCM credentials OK, project:', c.project_id)\"",
        timeout=60,
    )

    print(f"\nFirebase configured for project: {project_id}")
    print(f"Check: https://lumin.tahseen.tech/health")
    ssh.close()


if __name__ == "__main__":
    if "DEPLOY_PASSWORD" not in os.environ:
        print("Set DEPLOY_PASSWORD", file=sys.stderr)
        sys.exit(1)
    main()
