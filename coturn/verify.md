# Coturn Verification Guide

## Prerequisites

- `install.sh` has been run and `systemctl status coturn` shows **active (running)**.
- Firewall rules from `firewall.sh --yes` have been applied (ports 3478, 5349, 49152-65535 open).
- DNS for `$DOMAIN` resolves to `$VPS_PUBLIC_IP`.
- TLS certificate exists at `/etc/letsencrypt/live/$DOMAIN/` (prompt 10). Port 5349
  will be down until the cert is issued; all other checks work without it.

---

## 1. Service status

```bash
sudo systemctl status coturn
```

Expected: `active (running)`. If not:
```bash
sudo journalctl -u coturn -n 50 --no-pager
sudo cat /var/log/coturn/turnserver.log
```

---

## 2. STUN smoke test with turnutils_uclient

`turnutils_uclient` is included in the `coturn` package.

```bash
# Plain STUN binding (no auth needed)
turnutils_stunclient $DOMAIN

# TURN allocation with HMAC credentials
# USERNAME format expected by Coturn: "{unix_expiry}:{any_string}"
EXPIRY=$(( $(date +%s) + 3600 ))
USERNAME="${EXPIRY}:smoketest"
# Compute HMAC-SHA1 of username with your TURN_SECRET
CREDENTIAL=$(echo -n "$USERNAME" | openssl dgst -sha1 -hmac "$TURN_SECRET" -binary | base64)

turnutils_uclient \
  -T \
  -u "$USERNAME" \
  -w "$CREDENTIAL" \
  $DOMAIN
```

Expected: allocation succeeds, data relayed, no authentication errors.

---

## 3. TLS / TURNS check (port 5349)

```bash
openssl s_client -connect $DOMAIN:5349 -servername $DOMAIN < /dev/null 2>&1 \
  | grep -E 'Verify|subject|issuer|DONE'
```

Expected: certificate from Let's Encrypt, `Verify return code: 0 (ok)`.

---

## 4. End-to-end relay test with the Trickle-ICE tool

1. Open [https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/)

2. Obtain credentials from the FastAPI server:
   ```bash
   # Register/login first, then:
   curl -H "Authorization: Bearer $TOKEN" https://$DOMAIN/api/auth/turn-credentials
   ```
   Returns:
   ```json
   {
     "username": "1234567890:userId",
     "credential": "base64string==",
     "ttl": 86400,
     "uris": [
       "stun:lumin.example.com:3478",
       "turn:lumin.example.com:3478",
       "turns:lumin.example.com:5349"
     ]
   }
   ```

3. In the Trickle-ICE tool:
   - Add ICE server: `turn:$DOMAIN:3478`
   - Username: the `username` from the API response
   - Credential: the `credential` from the API response
   - Click **Gather candidates**

4. Expected output: at least one candidate with type **`relay`** appears.
   If only `host` and `srflx` appear, TURN relay is blocked — check the firewall.

---

## 5. Log monitoring during a test call

```bash
tail -f /var/log/coturn/turnserver.log
```

During a call you should see allocation requests, permission grants, and data
channel activity. No `ERROR` or `auth failed` lines should appear.

---

## 6. Certificate renewal verification

After a cert renewal (manual or automatic):

```bash
# Simulate renewal
sudo certbot renew --dry-run

# Or trigger the deploy hook directly
sudo /etc/letsencrypt/renewal-hooks/deploy/reload-coturn.sh

# Confirm Coturn reloaded without restarting
sudo systemctl status coturn
# Should still show the original start time, not a new one
```

---

## Certificate dependency note

`install.sh` should be run **after** `certbot certonly` has issued the certificate.
If you install Coturn before the cert exists:
- Coturn starts successfully on port 3478 (STUN/TURN over UDP/TCP).
- Port 5349 (TURNS/TLS) will **not** open until the cert files exist.
- Once the cert is issued, `sudo systemctl restart coturn` will bring 5349 up.
- Going forward, the `certbot-deploy-hook.sh` keeps the cert fresh automatically.

---

## Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `Authentication failed` | `TURN_SECRET` mismatch between Coturn and FastAPI | Verify both use same `TURN_SECRET` from `.env` |
| No `relay` candidate | UDP 49152-65535 blocked | Re-run `firewall.sh --yes`, check DO Cloud Firewall |
| Port 5349 refused | Cert not yet issued | Run `certbot certonly` first (prompt 10) |
| Coturn won't start | Config syntax error | `sudo turnserver -c /etc/turnserver.conf --check` |
| `lt-cred-mech` conflict | Old config leftover | Remove `lt-cred-mech` from `/etc/turnserver.conf` |
