#!/usr/bin/env bash
# =============================================================================
# deploy/issue-cert.sh — First-time TLS cert issuance and nginx SSL activation
#
# Usage (run as root on the VPS from the project directory):
#   export DOMAIN=lumin.example.com
#   export EMAIL=admin@example.com
#   sudo -E bash deploy/issue-cert.sh
#
# What it does:
#   1. Issues a Let's Encrypt cert via certbot webroot challenge
#   2. Substitutes ${DOMAIN} in nginx/ssl.conf.template
#   3. Writes the resolved config to nginx/conf.d/lumin.conf
#   4. Tests and reloads nginx
#   5. Installs a certbot deploy hook that reloads nginx on every renewal
#
# Prerequisites:
#   - certbot installed: sudo apt-get install -y certbot
#   - Docker Compose stack running with bootstrap config:
#       docker compose up -d
#   - DNS for $DOMAIN pointing to this server's public IP
#   - Port 80 open and reachable from the internet (ACME challenge)
# =============================================================================
set -euo pipefail

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"

if [[ -z "$DOMAIN" ]]; then
  echo "ERROR: DOMAIN is required." >&2
  echo "  export DOMAIN=lumin.example.com" >&2
  exit 1
fi

if [[ -z "$EMAIL" ]]; then
  echo "ERROR: EMAIL is required for Let's Encrypt registration." >&2
  echo "  export EMAIL=admin@example.com" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF_TEMPLATE="$PROJECT_ROOT/nginx/ssl.conf.template"
CONF_DEST="$PROJECT_ROOT/nginx/conf.d/lumin.conf"
WEBROOT="/var/www/certbot"
COMPOSE="docker compose -f $PROJECT_ROOT/docker-compose.yml -f $PROJECT_ROOT/docker-compose.prod.yml"

# ── 1. Sanity checks ─────────────────────────────────────────────────────────

if ! command -v certbot &>/dev/null; then
  echo "ERROR: certbot not found." >&2
  echo "  sudo apt-get install -y certbot" >&2
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found." >&2
  exit 1
fi

if [[ ! -f "$CONF_TEMPLATE" ]]; then
  echo "ERROR: SSL template not found at $CONF_TEMPLATE" >&2
  exit 1
fi

# ── 2. Webroot directory ──────────────────────────────────────────────────────

echo "==> Creating ACME webroot $WEBROOT..."
mkdir -p "$WEBROOT"

# ── 3. Verify nginx bootstrap config is valid and running ────────────────────

echo "==> Verifying nginx bootstrap config..."
if ! $COMPOSE exec -T nginx nginx -t; then
  echo "ERROR: nginx config test failed. Fix the config before continuing." >&2
  exit 1
fi

echo "==> Checking nginx is responding on port 80..."
if ! curl -fsS --max-time 5 "http://localhost/health" &>/dev/null; then
  echo "WARNING: /health is not responding on localhost:80." >&2
  echo "  Ensure the stack is running: docker compose up -d" >&2
fi

# ── 4. Issue certificate ──────────────────────────────────────────────────────

echo "==> Requesting Let's Encrypt certificate for $DOMAIN..."
certbot certonly \
  --webroot \
  --webroot-path "$WEBROOT" \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --domain "$DOMAIN" \
  --rsa-key-size 4096

echo "==> Certificate issued: /etc/letsencrypt/live/$DOMAIN/"

# ── 5. Generate SSL nginx config from template ───────────────────────────────

echo "==> Generating SSL nginx config..."
sed "s|\${DOMAIN}|$DOMAIN|g" "$CONF_TEMPLATE" > "$CONF_DEST"

echo "    Written: $CONF_DEST"

# ── 6. Verify resolved config has no remaining placeholders ──────────────────

if grep -q '\${DOMAIN}' "$CONF_DEST"; then
  echo "ERROR: Unresolved placeholders remain in $CONF_DEST" >&2
  exit 1
fi

# ── 7. Test and reload nginx ──────────────────────────────────────────────────

echo "==> Testing nginx SSL config..."
$COMPOSE exec -T nginx nginx -t

echo "==> Reloading nginx..."
$COMPOSE exec -T nginx nginx -s reload

# ── 8. Install certbot deploy hook for automatic renewals ────────────────────

HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
HOOK_FILE="$HOOK_DIR/reload-nginx.sh"

echo "==> Installing certbot renewal deploy hook at $HOOK_FILE..."
mkdir -p "$HOOK_DIR"
cat > "$HOOK_FILE" <<EOF
#!/usr/bin/env bash
# Reload nginx after certbot renews the certificate (no downtime).
docker compose -f $PROJECT_ROOT/docker-compose.yml -f $PROJECT_ROOT/docker-compose.prod.yml exec -T nginx nginx -s reload
EOF
chmod +x "$HOOK_FILE"

echo ""
echo "================================================================"
echo " TLS certificate issued — nginx is now serving HTTPS."
echo "================================================================"
echo ""
echo "  Domain  : https://$DOMAIN"
echo "  Cert    : /etc/letsencrypt/live/$DOMAIN/"
echo "  Hook    : $HOOK_FILE"
echo ""
echo "Next steps:"
echo ""
echo "  1. Install the auto-renewal cron job:"
echo "       sudo cp $SCRIPT_DIR/renew-cron /etc/cron.d/lumin-certbot"
echo "       sudo chmod 644 /etc/cron.d/lumin-certbot"
echo ""
echo "  2. (Optional) Harden TLS with Diffie-Hellman parameters:"
echo "       sudo bash $SCRIPT_DIR/dh-and-headers.sh"
echo ""
echo "  3. Verify TLS:"
echo "       curl -I https://$DOMAIN/health"
echo "       openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null"
echo ""
echo "  4. Full verification checklist: nginx/VERIFY.md"
