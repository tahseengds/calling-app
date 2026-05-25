#!/usr/bin/env bash
# =============================================================================
# coturn/certbot-deploy-hook.sh
#
# Certbot deploy hook — reload Coturn after a certificate renewal so it picks
# up the new cert/key without a full restart (no call interruption).
#
# Installation:
#   sudo cp coturn/certbot-deploy-hook.sh \
#        /etc/letsencrypt/renewal-hooks/deploy/reload-coturn.sh
#   sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-coturn.sh
#
# Certbot runs all executable files in renewal-hooks/deploy/ after a successful
# renewal. This hook is also referenced by the Nginx prompt (prompt 10).
#
# Test manually (simulates a renewal):
#   sudo certbot renew --dry-run
# =============================================================================
set -euo pipefail

DOMAIN="${RENEWED_DOMAINS%% *}"
COTURN_CERT_DIR="/etc/coturn/ssl"
LE_LIVE="/etc/letsencrypt/live/${DOMAIN}"

if [[ -n "$DOMAIN" && -f "$LE_LIVE/fullchain.pem" && -f "$LE_LIVE/privkey.pem" ]]; then
  install -d -m 750 -o turnserver -g turnserver "$COTURN_CERT_DIR"
  cp -L "$LE_LIVE/fullchain.pem" "$COTURN_CERT_DIR/fullchain.pem"
  cp -L "$LE_LIVE/privkey.pem" "$COTURN_CERT_DIR/privkey.pem"
  chown turnserver:turnserver "$COTURN_CERT_DIR"/*.pem
  chmod 640 "$COTURN_CERT_DIR/privkey.pem"
  chmod 644 "$COTURN_CERT_DIR/fullchain.pem"
fi

if systemctl is-active --quiet coturn; then
  echo "Reloading Coturn to pick up renewed certificate..."
  systemctl reload coturn
  echo "Coturn reloaded successfully."
else
  echo "Coturn is not running — skipping reload."
fi
