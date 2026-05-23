#!/usr/bin/env bash
# =============================================================================
# coturn/install.sh — Idempotent Coturn install and configuration
#
# Usage:
#   export VPS_PUBLIC_IP=1.2.3.4
#   export DOMAIN=family.example.com
#   export TURN_SECRET=your-secret-here
#   sudo -E bash coturn/install.sh
#
# Or pass variables as arguments:
#   sudo bash coturn/install.sh 1.2.3.4 family.example.com your-secret
#
# Safe to re-run — each step is checked before executing.
# Run AFTER certbot has issued the certificate (see verify.md); Coturn starts
# without TLS (port 5349 down) if the cert files do not exist yet.
# =============================================================================
set -euo pipefail

# ── Argument / env handling ───────────────────────────────────────────────────
VPS_PUBLIC_IP="${1:-${VPS_PUBLIC_IP:-}}"
DOMAIN="${2:-${DOMAIN:-}}"
TURN_SECRET="${3:-${TURN_SECRET:-}}"

if [[ -z "$TURN_SECRET" ]]; then
  echo "ERROR: TURN_SECRET is required." >&2
  echo "  export TURN_SECRET=<secret>  OR  pass as third argument." >&2
  exit 1
fi

if [[ -z "$VPS_PUBLIC_IP" ]]; then
  echo "ERROR: VPS_PUBLIC_IP is required." >&2
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "ERROR: DOMAIN is required." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_TEMPLATE="$SCRIPT_DIR/turnserver.conf"
COTURN_CONF="/etc/turnserver.conf"
COTURN_DEFAULT="/etc/default/coturn"
LOG_DIR="/var/log/coturn"

echo "==> Installing Coturn..."
if dpkg -s coturn &>/dev/null; then
  echo "    coturn already installed, skipping apt."
else
  apt-get update -qq
  apt-get install -y coturn
fi

echo "==> Enabling Coturn service in $COTURN_DEFAULT..."
if grep -qE '^TURNSERVER_ENABLED=1' "$COTURN_DEFAULT" 2>/dev/null; then
  echo "    Already enabled."
else
  # Replace or append the directive
  if grep -qE '^#?TURNSERVER_ENABLED' "$COTURN_DEFAULT" 2>/dev/null; then
    sed -i 's/^#*TURNSERVER_ENABLED.*/TURNSERVER_ENABLED=1/' "$COTURN_DEFAULT"
  else
    echo "TURNSERVER_ENABLED=1" >> "$COTURN_DEFAULT"
  fi
fi

echo "==> Creating log directory $LOG_DIR..."
mkdir -p "$LOG_DIR"
chown -R turnserver:turnserver "$LOG_DIR" 2>/dev/null || true

echo "==> Writing $COTURN_CONF from template..."
if [[ ! -f "$CONF_TEMPLATE" ]]; then
  echo "ERROR: Template not found at $CONF_TEMPLATE" >&2
  exit 1
fi

# Substitute placeholders using sed (avoids envsubst dependency)
sed \
  -e "s|\${VPS_PUBLIC_IP}|$VPS_PUBLIC_IP|g" \
  -e "s|\${DOMAIN}|$DOMAIN|g" \
  -e "s|\${TURN_SECRET}|$TURN_SECRET|g" \
  "$CONF_TEMPLATE" > "$COTURN_CONF"

chmod 640 "$COTURN_CONF"
chown root:turnserver "$COTURN_CONF" 2>/dev/null || true

echo "==> Verifying substitution (no placeholders should remain)..."
if grep -qE '\$\{(VPS_PUBLIC_IP|DOMAIN|TURN_SECRET)\}' "$COTURN_CONF"; then
  echo "ERROR: Unresolved placeholders in $COTURN_CONF" >&2
  grep -E '\$\{' "$COTURN_CONF" >&2
  exit 1
fi

echo "==> Enabling and restarting Coturn..."
systemctl enable coturn
systemctl restart coturn

echo ""
echo "================================================================"
echo " Coturn installed successfully."
echo "================================================================"
echo ""
echo "Verification steps:"
echo "  1. Check service status:"
echo "       sudo systemctl status coturn"
echo ""
echo "  2. STUN smoke test (install: apt install coturn):"
echo "       turnutils_uclient -T $VPS_PUBLIC_IP"
echo ""
echo "  3. TLS check (requires cert — see verify.md):"
echo "       openssl s_client -connect $DOMAIN:5349 -servername $DOMAIN"
echo ""
echo "  4. Full relay test:"
echo "       See coturn/verify.md for the Trickle-ICE web tool instructions."
echo ""
echo "  5. Watch logs:"
echo "       tail -f $LOG_DIR/turnserver.log"
echo ""
echo "NOTE: If /etc/letsencrypt/live/$DOMAIN/ does not exist yet,"
echo "      port 5349 (TLS) will be down until certs are issued (prompt 10)."
echo "      After cert renewal, run:"
echo "       sudo systemctl reload coturn"
echo "      or install coturn/certbot-deploy-hook.sh to do it automatically."
