#!/usr/bin/env python3
# Usage:
#   export DEPLOY_HOST=<vps-ip>
#   export DEPLOY_PASSWORD=<ssh-password>
#   export TURN_SECRET=<secret-from-dotenv>   # rotate the old one — it was leaked
#   python deploy/finish_deploy.py
import os
import sys

import paramiko

HOST = os.environ["DEPLOY_HOST"]          # never hard-code the server IP
PASSWORD = os.environ["DEPLOY_PASSWORD"]
TURN_SECRET = os.environ["TURN_SECRET"]   # never hard-code — was leaked, must rotate
REMOTE = "/opt/lumin"


def _validate_env() -> None:
    missing = [k for k in ("DEPLOY_HOST", "DEPLOY_PASSWORD", "TURN_SECRET") if not os.environ.get(k)]
    if missing:
        print(f"Missing required env vars: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)


def run(ssh, cmd, timeout=600):
    print(f">>> {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    if code != 0:
        raise SystemExit(code)


def main():
    _validate_env()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username="root", password=PASSWORD, timeout=60)

    run(ssh, "apt-get install -y -qq dos2unix")
    run(ssh, f'find {REMOTE} -name "*.sh" -exec dos2unix {{}} +')
    run(
        ssh,
        f"cd {REMOTE} && docker compose -f docker-compose.yml -f docker-compose.prod.yml "
        "exec -T fastapi alembic stamp head",
    )
    run(
        ssh,
        f"cd {REMOTE} && VPS_PUBLIC_IP={HOST} DOMAIN={HOST} "
        f"TURN_SECRET={TURN_SECRET} bash coturn/install.sh",
    )
    run(ssh, f"cd {REMOTE} && bash coturn/firewall.sh --yes", timeout=120)
    run(ssh, f"curl -fsS http://{HOST}/health")
    run(ssh, "systemctl is-active coturn")
    ssh.close()
    print("Post-deploy steps complete.")


if __name__ == "__main__":
    main()
