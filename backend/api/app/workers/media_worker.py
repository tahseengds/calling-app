"""
Media Worker — stub for async media processing via Redis Streams.

Prompt 06 chose inline processing (Pillow / FFmpeg run inside the FastAPI request),
which is adequate for a 10-user family app. This file is a documented stub that mirrors
the fcm_worker structure so it can be enabled later without restructuring.

To activate:
  1. In media_service.upload_media(), replace inline process_image/process_video/
     process_audio calls with an XADD to the "media_processing" stream.
  2. Implement the consumer group loop below, calling the same service functions.
  3. Add a "media_worker" service to docker-compose.yml alongside "fcm_worker".

Stream name:  media_processing
Group name:   media_workers
Consumer:     media-worker-1
"""
from __future__ import annotations

import asyncio
import logging

from app.config import settings

logger = logging.getLogger(__name__)

MEDIA_STREAM = "media_processing"
CONSUMER_GROUP = "media_workers"
CONSUMER_NAME = "media-worker-1"


async def run_worker() -> None:
    """Placeholder — not yet implemented (inline processing is used instead)."""
    logging.basicConfig(
        level=logging.DEBUG if settings.DEBUG else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    logger.info(
        "Media worker stub: inline processing is active. "
        "Implement this worker to offload heavy transcoding."
    )
    # Prevent the process from exiting immediately so Docker doesn't restart-loop.
    while True:
        await asyncio.sleep(60)


if __name__ == "__main__":
    asyncio.run(run_worker())
