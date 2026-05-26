#!/usr/bin/env python3
import os
import sys

import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = "165.227.146.247"
SSH_KEY = os.path.expanduser(os.environ.get("DEPLOY_KEY", "~/.ssh/do_droplet"))

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="root", key_filename=SSH_KEY)

cmds = [
    "systemctl is-active coturn",
    "ss -lntup | grep -E '3478|5349' || true",
    "grep -E 'cert|pkey|listening' /etc/turnserver.conf",
    "ls /etc/letsencrypt/live/lumin.tahseen.tech/ 2>&1",
    "tail -20 /var/log/coturn/turnserver.log 2>&1",
    '''docker exec lumin-fastapi-1 python -c "
import httpx
try:
    r = httpx.get('https://lumin.tahseen.tech/health?format=json', timeout=5, verify=False)
    print('status', r.status_code)
except Exception as e:
    print('error', type(e).__name__, e)
"''',
    '''docker exec lumin-fastapi-1 python -c "
import socket
for port in (3478, 5349):
    s = socket.socket()
    s.settimeout(3)
    try:
        s.connect(('lumin.tahseen.tech', port))
        print(port, 'open')
    except Exception as e:
        print(port, 'fail', e)
    finally:
        s.close()
"''',
]
for cmd in cmds:
    print("===", cmd[:70])
    _, o, e = c.exec_command(cmd, timeout=30)
    print(o.read().decode())
    err = e.read().decode()
    if err:
        print("stderr:", err)
c.close()
