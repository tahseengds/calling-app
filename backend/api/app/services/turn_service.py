"""
TURN/STUN credential generation — Coturn `use-auth-secret` mechanism.

Algorithm (must match Coturn's static-auth-secret verification):
  timestamp = now_epoch + ttl
  username  = "{timestamp}:{user_id}"
  credential = base64( HMAC-SHA1(TURN_SECRET, username) )

Reference: https://coturn.net/turnserver/
           https://www.rfc-editor.org/rfc/rfc5766
"""
import base64
import hashlib
import hmac
import time

import redis.asyncio as aioredis

from app.config import settings
from app.schemas.turn import TurnCredentialsResponse


async def generate_turn_credentials(
    redis: aioredis.Redis,
    user_id: str,
    ttl: int = 3600,
) -> TurnCredentialsResponse:
    cache_key = f"turn_creds:{user_id}"

    cached = await redis.get(cache_key)
    if cached:
        return TurnCredentialsResponse.model_validate_json(cached)

    timestamp = int(time.time()) + ttl
    username = f"{timestamp}:{user_id}"

    # HMAC-SHA1 with the shared TURN_SECRET — Coturn verifies this server-side
    credential = base64.b64encode(
        hmac.new(
            settings.TURN_SECRET.encode("utf-8"),
            username.encode("utf-8"),
            hashlib.sha1,
        ).digest()
    ).decode("utf-8")

    response = TurnCredentialsResponse(
        username=username,
        credential=credential,
        ttl=ttl,
        uris=[
            f"stun:{settings.TURN_HOST}:3478",
            f"turn:{settings.TURN_HOST}:3478",
            f"turn:{settings.TURN_HOST}:3478?transport=tcp",
            f"turns:{settings.TURN_HOST}:5349",
        ],
    )

    # Cache slightly under TTL so credentials are refreshed before they expire
    await redis.setex(cache_key, max(ttl - 60, 1), response.model_dump_json())
    return response
