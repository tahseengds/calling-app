# Nginx Verification Guide

## Prerequisites

- Docker Compose stack is running: `docker compose up -d`
- `$DOMAIN` DNS resolves to the server's public IP
- Port 80 and 443 are open

---

## 1. Bootstrap config (before TLS cert)

### nginx starts cleanly

```bash
docker compose exec nginx nginx -t
# Expected: syntax is ok / test is successful

docker compose ps nginx
# Expected: Up
```

### ACME challenge directory is accessible

```bash
sudo mkdir -p /var/www/certbot
echo "test" | sudo tee /var/www/certbot/.well-known/acme-challenge/probe
curl http://$DOMAIN/.well-known/acme-challenge/probe
# Expected: test
sudo rm -f /var/www/certbot/.well-known/acme-challenge/probe
```

### Health endpoint

```bash
curl http://$DOMAIN/health
# Expected: {"status":"ok"} or similar from FastAPI
```

---

## 2. Issue TLS certificate

```bash
export DOMAIN=family.example.com
export EMAIL=admin@example.com
sudo -E bash deploy/issue-cert.sh
```

Expected output ends with "TLS certificate issued — nginx is now serving HTTPS."

---

## 3. TLS verification

### HTTPS health check

```bash
curl -I https://$DOMAIN/health
# Expected: HTTP/2 200
```

### Certificate details

```bash
openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null 2>&1 \
  | grep -E 'subject|issuer|Verify|Protocol|Cipher'
# Expected:
#   subject=/CN=family.example.com
#   issuer=Let's Encrypt
#   Verify return code: 0 (ok)
#   Protocol: TLSv1.3 (or TLSv1.2)
```

### HTTP → HTTPS redirect

```bash
curl -I http://$DOMAIN/api/auth/login
# Expected: HTTP/1.1 301 and Location: https://...
```

### SSL Labs grade (optional, external tool)

Open: https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN
Expected: A or A+

---

## 4. Security headers

```bash
curl -sI https://$DOMAIN/health | grep -iE \
  'strict-transport|x-content-type|x-frame|referrer|permissions'
# Expected all five headers present
```

---

## 5. API proxy

```bash
curl -s https://$DOMAIN/health
# Expected: FastAPI health response

curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/api/auth/login \
  -X POST -H "Content-Type: application/json" -d '{}'
# Expected: 422 (validation error from FastAPI, not nginx 502)
```

---

## 6. Signaling WebSocket

Using a browser or wscat:

```bash
npm install -g wscat
wscat -c "wss://$DOMAIN/signal?EIO=4&transport=websocket" \
  --header "Authorization: Bearer <token>"
# Expected: connects (101 Upgrade), then Socket.IO handshake payload
```

### Signaling health (external endpoint)

```bash
curl -s https://$DOMAIN/signal/health
# Expected: {"status":"ok"}
```

---

## 7. Auto-renewal

### Install cron and test

```bash
sudo cp deploy/renew-cron /etc/cron.d/familylink-certbot
sudo chmod 644 /etc/cron.d/familylink-certbot

# Simulate a renewal (no actual renewal if cert is fresh)
sudo certbot renew --dry-run
# Expected: Congratulations, all simulated renewals succeeded / no changes needed
```

### Verify deploy hook is installed

```bash
cat /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
# Expected: contains 'docker compose ... nginx -s reload'

sudo bash /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
# Expected: nginx reload succeeds (no error output)
```

---

## 8. Log monitoring

```bash
docker compose logs -f nginx
```

During normal operation:
- Access log lines for each request
- No `upstream connect error` lines

Possible issues:

| Symptom | Likely cause | Fix |
|---|---|---|
| `502 Bad Gateway` | Upstream container not running | `docker compose ps`, check service health |
| `SSL_ERROR_RX_RECORD_TOO_LONG` | Port 443 serving HTTP | Check `listen 443 ssl` in config |
| `curl: (60) SSL cert not OK` | Cert not yet issued | Run `deploy/issue-cert.sh` |
| `/health` returns 404 | FastAPI health route missing | Check `GET /health` in FastAPI |
| WebSocket 400 | Hitting `/signal/health` as WS | Use `/signal` for socket, `/signal/health` for HTTP |
| `auth_request` 500 | `/api/media/auth` endpoint missing | Implement media auth route in FastAPI |
