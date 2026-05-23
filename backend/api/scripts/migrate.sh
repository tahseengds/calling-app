#!/usr/bin/env sh
# Run Alembic migrations to the latest revision.
# init.sql handles first-boot schema; this script handles subsequent upgrades.
set -e
cd "$(dirname "$0")/.."
alembic upgrade head
