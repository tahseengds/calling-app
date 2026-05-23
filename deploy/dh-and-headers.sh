#!/usr/bin/env bash
# =============================================================================
# deploy/dh-and-headers.sh — Optional TLS hardening: Diffie-Hellman parameters
#
# Generates a 2048-bit DH params file and activates it inside the running
# nginx container. Adds the ssl_dhparam directive to the live nginx config.
#
# Usage (run as root after deploy/issue-cert.sh):
#   sudo bash deploy/dh-and-headers.sh
#
# The DH params are stored inside the container at /etc/nginx/dhparam.pem.
# They survive nginx reloads but are lost on container restart — re-run this
# script after container recreation (e.g., after 'docker compose up -d --build').
#
# Why: TLS 1.3 uses ECDHE exclusively (no DHE), so DHE params only matter for
# TLS 1.2 clients. Modern clients use TLS 1.3; this is belt-and-suspenders.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_FILE="$PROJECT_ROOT/nginx/conf.d/familyapp.conf"
COMPOSE="docker compose -f $PROJECT_ROOT/docker-compose.yml"

# ── Check prerequisites ───────────────────────────────────────────────────────

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: $CONF_FILE not found. Run deploy/issue-cert.sh first." >&2
  exit 1
fi

if ! $COMPOSE exec -T nginx true &>/dev/null; then
  echo "ERROR: nginx container is not running." >&2
  echo "  docker compose up -d" >&2
  exit 1
fi

# ── Generate DH params ────────────────────────────────────────────────────────

TMPFILE="$(mktemp /tmp/dhparam.XXXXXX.pem)"
trap 'rm -f "$TMPFILE"' EXIT

echo "==> Generating 2048-bit DH parameters (this may take a minute)..."
openssl dhparam -out "$TMPFILE" 2048

echo "==> Copying DH params into nginx container..."
NGINX_CONTAINER=$($COMPOSE ps -q nginx)
docker cp "$TMPFILE" "$NGINX_CONTAINER:/etc/nginx/dhparam.pem"

# ── Patch nginx config ────────────────────────────────────────────────────────

echo "==> Patching $CONF_FILE to add ssl_dhparam directive..."

if grep -q 'ssl_dhparam' "$CONF_FILE"; then
  echo "    ssl_dhparam already present — skipping patch."
else
  # Insert after ssl_session_tickets line
  sed -i 's|ssl_session_tickets.*off;|&\n    ssl_dhparam          /etc/nginx/dhparam.pem;|' "$CONF_FILE"
  echo "    ssl_dhparam directive added."
fi

# ── Test and reload ───────────────────────────────────────────────────────────

echo "==> Testing nginx config..."
$COMPOSE exec -T nginx nginx -t

echo "==> Reloading nginx..."
$COMPOSE exec -T nginx nginx -s reload

echo ""
echo "================================================================"
echo " DH parameters active. nginx reloaded."
echo "================================================================"
echo ""
echo "NOTE: DH params live inside the container and are lost on restart."
echo "Re-run this script after 'docker compose up -d --build' or similar."
echo ""
echo "Verify DHE in use:"
echo "  openssl s_client -connect \$DOMAIN:443 -cipher DHE-RSA-AES128-GCM-SHA256 < /dev/null"
