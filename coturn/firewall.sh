#!/usr/bin/env bash
# =============================================================================
# coturn/firewall.sh — Open required ports for Coturn with ufw
#
# Usage:
#   sudo bash coturn/firewall.sh --yes
#
# Without --yes the script prints what it would do and exits (dry-run).
#
# Required ports:
#   UDP 3478          STUN / TURN (plain)
#   TCP 3478          TURN over TCP (firewall traversal)
#   TCP 5349          TURNS / TLS
#   UDP 49152-65535   TURN media relay
#
# Ports this script NEVER touches (preserved):
#   TCP 22   SSH
#   TCP 80   HTTP (Nginx / certbot)
#   TCP 443  HTTPS (Nginx)
#
# DigitalOcean Cloud Firewall equivalent rules (manage in the DO dashboard
# or via doctl / Terraform — these are NOT applied by this script):
#
#   Inbound rules:
#     Protocol  Port(s)         Sources
#     UDP       3478            All IPv4, All IPv6
#     TCP       3478            All IPv4, All IPv6
#     TCP       5349            All IPv4, All IPv6
#     UDP       49152-65535     All IPv4, All IPv6
#     TCP       22              (restrict to your IPs in production)
#     TCP       80              All IPv4, All IPv6
#     TCP       443             All IPv4, All IPv6
# =============================================================================
set -euo pipefail

APPLY=false

for arg in "$@"; do
  if [[ "$arg" == "--yes" ]]; then
    APPLY=true
  fi
done

# ── Dry-run notice ────────────────────────────────────────────────────────────
if [[ "$APPLY" != true ]]; then
  echo "DRY RUN — no changes will be made."
  echo "Re-run with --yes to apply."
  echo ""
  echo "Would execute the following ufw commands:"
  echo "  ufw allow 22/tcp        # SSH (ensure not dropped)"
  echo "  ufw allow 80/tcp        # HTTP"
  echo "  ufw allow 443/tcp       # HTTPS"
  echo "  ufw allow 3478/udp      # STUN / TURN"
  echo "  ufw allow 3478/tcp      # TURN over TCP"
  echo "  ufw allow 5349/tcp      # TURNS / TLS"
  echo "  ufw allow 49152:65535/udp  # TURN media relay"
  echo ""
  echo "WARNING: Applying firewall rules can lock you out if SSH is not open."
  echo "Verify 'ufw status' before enabling if ufw is not yet active."
  exit 0
fi

# ── Safety check ─────────────────────────────────────────────────────────────
echo "==> Ensuring SSH (TCP 22) is allowed before any changes..."
ufw allow 22/tcp comment "SSH"

echo "==> Ensuring HTTP/HTTPS are allowed..."
ufw allow 80/tcp  comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

echo "==> Opening Coturn ports..."
ufw allow 3478/udp comment "STUN/TURN"
ufw allow 3478/tcp comment "TURN-TCP"
ufw allow 5349/tcp comment "TURNS-TLS"
ufw allow 49152:65535/udp comment "TURN-relay"

echo "==> Enabling ufw (if not already active)..."
# 'ufw --force enable' is idempotent and won't drop existing connections
ufw --force enable

echo ""
echo "==> Current ufw status:"
ufw status verbose

echo ""
echo "================================================================"
echo " Firewall rules applied successfully."
echo " SSH (TCP 22) is open — you are not locked out."
echo "================================================================"
echo ""
echo "REMINDER: If you use DigitalOcean Cloud Firewall, also add the"
echo "equivalent inbound rules in the DO dashboard (see comments at the"
echo "top of this script). ufw and DO Cloud Firewall operate independently."
