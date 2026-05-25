#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "165.227.146.247"
PASSWORD = __import__("os").environ["DEPLOY_PASSWORD"]
ROOT = Path(__file__).resolve().parents[1]

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="root", password=PASSWORD)

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
    "TURN_SECRET=80c0816fed2f1aa8339f9630e9393ec78acfa6a5adb549376382a09715b134f6 "
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
