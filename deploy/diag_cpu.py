#!/usr/bin/env python3
"""Diagnose high CPU on the Lumin VPS."""
import os
import sys

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "165.227.146.247"
SSH_KEY = os.path.expanduser(os.environ.get("DEPLOY_KEY", "~/.ssh/do_droplet"))

cmds = [
    "uptime; free -h; df -h /",
    "top -b -n1 -o %CPU | head -25",
    "ps aux --sort=-%cpu | head -15",
    "docker stats --no-stream",
    "docker compose -f /opt/lumin/docker-compose.yml -f /opt/lumin/docker-compose.prod.yml ps -a",
    "for c in lumin-fastapi-1 lumin-worker-1 lumin-signaling-1 lumin-postgres-1 lumin-redis-1 lumin-nginx-1; do echo \"=== $c restart count ===\"; docker inspect -f '{{.RestartCount}} {{.State.Status}}' $c 2>/dev/null || echo missing; done",
    "docker logs lumin-worker-1 --tail 30 2>&1",
    "docker logs lumin-fastapi-1 --tail 20 2>&1",
    "docker logs lumin-signaling-1 --tail 20 2>&1",
    "redis-cli -h 127.0.0.1 -p 6379 INFO stats 2>/dev/null | grep -E 'total_commands|instantaneous' || docker exec lumin-redis-1 redis-cli INFO stats | grep -E 'total_commands|instantaneous'",
    "XLEN fcm_queue 2>/dev/null || docker exec lumin-redis-1 redis-cli XLEN fcm_queue",
    "systemctl is-active coturn; pgrep -a turnserver | head -3",
]

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="root", key_filename=SSH_KEY, timeout=30)
for cmd in cmds:
    print("\n" + "=" * 60)
    print(">>>", cmd[:70])
    _, o, e = c.exec_command(cmd, timeout=60)
    out = o.read().decode("utf-8", "replace")
    err = e.read().decode("utf-8", "replace")
    if out:
        print(out)
    if err.strip():
        print("stderr:", err[:800])
c.close()
