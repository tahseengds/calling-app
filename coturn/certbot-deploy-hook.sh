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

if systemctl is-active --quiet coturn; then
  echo "Reloading Coturn to pick up renewed certificate..."
  systemctl reload coturn
  echo "Coturn reloaded successfully."
else
  echo "Coturn is not running — skipping reload."
fi
