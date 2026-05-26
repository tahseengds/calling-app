"""One-shot: SSH to VPS and run a command on the fastapi container."""
import os
import sys

import paramiko

HOST = "165.227.146.247"
USER = "root"
KEY = os.path.expanduser("~/.ssh/do_droplet")


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else (
        "cd /opt/lumin && docker compose exec -T fastapi pytest "
        "tests/test_conversations_and_calls.py -v 2>&1"
    )
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, key_filename=KEY, timeout=60)
    _, stdout, _ = ssh.exec_command(cmd, get_pty=False, timeout=300)
    print(stdout.read().decode("utf-8", errors="replace"))
    ssh.close()


if __name__ == "__main__":
    main()
