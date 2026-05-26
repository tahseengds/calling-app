#!/usr/bin/env python3
"""Upload Lumin stack to VPS and start Docker Compose (excludes flutter_app)."""
from __future__ import annotations

import os
import stat
import sys
from pathlib import Path

import paramiko

HOST = os.environ.get("DEPLOY_HOST", "165.227.146.247")
USER = os.environ.get("DEPLOY_USER", "root")
PASSWORD = os.environ["DEPLOY_PASSWORD"]
REMOTE_DIR = os.environ.get("DEPLOY_DIR", "/opt/lumin")

SKIP_DIRS = {
    ".git",
    "flutter_app",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
    ".dart_tool",
    "build",
    "docs",
    ".cursor",
    "agent-transcripts",
    "terminals",
    "mcps",
}
SKIP_FILES = {".DS_Store", "firebase-service-account.json", "google-services.json"}
# NOTE: .env is intentionally NOT in SKIP_FILES — it is uploaded to the server.
# The git safety check below prevents it from being committed to the repo.


def should_skip(rel: Path) -> bool:
    parts = rel.parts
    if parts and parts[0] in SKIP_DIRS:
        return True
    return any(p in SKIP_DIRS for p in parts)


def upload_tree(sftp: paramiko.SFTPClient, local_root: Path, remote_root: str) -> None:
    for root, dirs, files in os.walk(local_root):
        rel_root = Path(root).relative_to(local_root)
        if should_skip(rel_root):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        remote_dir = remote_root if rel_root == Path(".") else f"{remote_root}/{rel_root.as_posix()}"
        try:
            sftp.stat(remote_dir)
        except OSError:
            sftp.mkdir(remote_dir)
        for name in files:
            if name in SKIP_FILES:
                continue
            rel = rel_root / name
            if should_skip(rel.parent):
                continue
            local_path = Path(root) / name
            remote_path = f"{remote_dir}/{name}"
            sftp.put(str(local_path), remote_path)


def run(ssh: paramiko.SSHClient, cmd: str, timeout: int = 1800) -> None:
    print(f"\n>>> {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode()
    err = stderr.read().decode()
    code = stdout.channel.recv_exit_status()
    if out:
        sys.stdout.buffer.write(out.encode("utf-8", "replace"))
        if not out.endswith("\n"):
            sys.stdout.buffer.write(b"\n")
    if err:
        sys.stderr.buffer.write(err.encode("utf-8", "replace"))
        if not err.endswith("\n"):
            sys.stderr.buffer.write(b"\n")
    if code != 0:
        raise RuntimeError(f"Command failed ({code}): {cmd}")


def _assert_env_not_tracked(local_root: Path) -> None:
    """Abort if .env is tracked by git — that would mean secrets are in the repo."""
    import subprocess
    env_path = local_root / ".env"
    if not env_path.exists():
        print("WARNING: no .env file found at project root — server may start without secrets.", file=sys.stderr)
        return
    result = subprocess.run(
        ["git", "-C", str(local_root), "ls-files", "--error-unmatch", ".env"],
        capture_output=True,
    )
    if result.returncode == 0:
        print(
            "ABORT: .env is tracked by git. Remove it with:\n"
            "  git rm --cached .env && echo '.env' >> .gitignore\n"
            "Then rotate any secrets it contained before deploying.",
            file=sys.stderr,
        )
        sys.exit(1)


def main() -> None:
    local_root = Path(__file__).resolve().parents[1]
    _assert_env_not_tracked(local_root)
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connecting to {USER}@{HOST}...")
    ssh.connect(HOST, username=USER, password=PASSWORD, timeout=60)

    run(
        ssh,
        "export DEBIAN_FRONTEND=noninteractive; "
        "command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh; "
        "systemctl enable --now docker; "
        "docker compose version >/dev/null 2>&1 || apt-get update -qq && "
        "apt-get install -y -qq docker-compose-plugin; "
        "mkdir -p /var/app-media /var/www/certbot " + REMOTE_DIR,
        timeout=600,
    )

    print("Uploading project files...")
    sftp = ssh.open_sftp()
    try:
        try:
            sftp.stat(REMOTE_DIR)
        except OSError:
            sftp.mkdir(REMOTE_DIR)
        upload_tree(sftp, local_root, REMOTE_DIR)
    finally:
        sftp.close()

    turn_secret = None
    env_path = local_root / ".env"
    for line in env_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("TURN_SECRET="):
            turn_secret = line.split("=", 1)[1].strip()
            break

    compose = (
        f"cd {REMOTE_DIR} && "
        "docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "up -d --build"
    )
    run(ssh, compose, timeout=1800)

    # Nginx caches DNS resolution for its upstream containers. When `up -d`
    # recreates fastapi / signaling, their internal IPs change and nginx
    # keeps proxying to the dead addresses → 502 on every request until
    # restarted. Force a restart here so deploys are atomic.
    run(
        ssh,
        f"cd {REMOTE_DIR} && "
        "docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "restart nginx",
        timeout=60,
    )

    run(ssh, "apt-get install -y -qq dos2unix && find " + REMOTE_DIR + ' -name "*.sh" -exec dos2unix {} +', timeout=120)
    run(
        ssh,
        f"cd {REMOTE_DIR} && docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "exec -T fastapi alembic stamp head",
        timeout=300,
    )

    if turn_secret:
        run(
            ssh,
            f"cd {REMOTE_DIR} && "
            f"export VPS_PUBLIC_IP={HOST} DOMAIN={HOST} TURN_SECRET='{turn_secret}' && "
            "bash coturn/install.sh",
            timeout=300,
        )
        run(ssh, f"cd {REMOTE_DIR} && bash coturn/firewall.sh --yes", timeout=120)

    run(ssh, f"curl -fsS http://127.0.0.1/health || curl -fsS http://localhost/health", timeout=30)
    print(f"\nDeploy complete. API: http://{HOST}/api/docs (if DEBUG)  Health: http://{HOST}/health")
    ssh.close()


if __name__ == "__main__":
    if "DEPLOY_PASSWORD" not in os.environ:
        print("Set DEPLOY_PASSWORD", file=sys.stderr)
        sys.exit(1)
    main()
