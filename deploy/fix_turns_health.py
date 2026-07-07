#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import os

HOST = "165.227.146.247"
SSH_KEY = os.path.expanduser(os.environ.get("DEPLOY_KEY", "~/.ssh/do_droplet"))
ROOT = Path(__file__).resolve().parents[1]

# The TURN shared secret must never be hardcoded in the repo (a leaked secret
# lets anyone mint TURN credentials and abuse the relay). Read it from the
# environment; it should match TURN_SECRET in the server's .env.
TURN_SECRET = os.environ.get("TURN_SECRET")
if not TURN_SECRET:
    sys.exit(
        "TURN_SECRET env var is required (e.g. `export TURN_SECRET=$(grep "
        "TURN_SECRET .env | cut -d= -f2)` on the server, or read it from your "
        "secret store). Refusing to run without it."
    )

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="root", key_filename=SSH_KEY)

sftp = c.open_sftp()
for rel in (
    "coturn/install.sh",
    "coturn/certbot-deploy-hook.sh",
    "backend/api/app/services/health_service.py",
):
    sftp.put(str(ROOT / rel), f"/opt/lumin/{rel}")
sftp.close()


def run(cmd: str, timeout: int = 600) -> int:
    print(">>>", cmd)
    _, o, e = c.exec_command(cmd, timeout=timeout)
    out = o.read().decode("utf-8", "replace")
    if out:
        print(out[-3000:])
    code = o.channel.recv_exit_status()
    if code:
        err = e.read().decode("utf-8", "replace")
        if err:
            print("stderr:", err[:500])
    return code


run('find /opt/lumin -name "*.sh" -exec dos2unix {} +')
run(
    "cd /opt/lumin && "
    "VPS_PUBLIC_IP=165.227.146.247 DOMAIN=lumin.tahseen.tech "
    f"TURN_SECRET={TURN_SECRET} "
    "bash coturn/install.sh"
)
run("ss -lntup | grep 5349 || echo '5349 not listening'")
run(
    "cd /opt/lumin && docker compose -f docker-compose.yml "
    "-f docker-compose.prod.yml up -d --build fastapi"
)
time.sleep(10)
_, o, _ = c.exec_command("curl -fsS https://lumin.tahseen.tech/health?format=json")
d = json.loads(o.read().decode())
print("\nstatus:", d["status"])
print("attention:", d.get("attention"))
for ch in d["checks"]:
    if ch["status"] != "ok":
        print(f"  {ch['name']}: {ch['message']}")
c.close()
