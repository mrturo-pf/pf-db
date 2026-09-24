#!/usr/bin/env bash
# ============================================================================
# export-neon-dump.sh - dump the Neon database to a local file
#
# Run this on a network that can actually resolve *.neon.tech (i.e. with the
# Corporative VPN DISCONNECTED). The corporate VPN's DNS does not resolve Neon's
# hostname and blocks unlisted egress, so this will fail while connected.
#
# Reads the connection string from secrets/neon.env (gitignored) instead of
# hardcoding it here -- copy secrets/neon.env.example if that file is missing.
#
# Output: secrets/neon_dump.sql (gitignored, plain SQL format).
# Next step: hand off to restore-neon-dump.sh to load it into the local DB.
#
# Plain SQL (-Fp) instead of the custom format (-Fc) on purpose: pg_dump's
# custom-format archive version depends on the *client* version that wrote
# it, and this script may run with a much newer local pg_dump (e.g. 18.x)
# than the local Postgres container (16.x) can read back with pg_restore.
# Plain SQL has no such archive-version coupling -- it just replays with
# psql, so it works regardless of client/server version skew.
#
# Usage:
#   scripts/export-neon-dump.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$ROOT_DIR/secrets"
ENV_FILE="$SECRETS_DIR/neon.env"
DUMP_FILE="$SECRETS_DIR/neon_dump.sql"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: missing $ENV_FILE"
  echo "Create it first: cp secrets/neon.env.example secrets/neon.env"
  echo "Then fill in NEON_DATABASE_URL with your real Neon connection string."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [ -z "${NEON_DATABASE_URL:-}" ]; then
  echo "ERROR: NEON_DATABASE_URL is not set in $ENV_FILE"
  exit 1
fi

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "ERROR: pg_dump not found on this machine."
  echo "Install the PostgreSQL client tools, e.g.: brew install libpq && brew link --force libpq"
  exit 1
fi

echo "Dumping Neon database..."
if ! pg_dump "$NEON_DATABASE_URL" --format=plain --no-owner --no-privileges --clean --if-exists -f "$DUMP_FILE"; then
  echo ""
  echo "ERROR: pg_dump failed."
  echo "Most likely cause: you're still connected to the Corporative VPN (its DNS"
  echo "cannot resolve *.neon.tech and blocks the connection). Disconnect the"
  echo "VPN and try again."
  rm -f "$DUMP_FILE"
  exit 1
fi

echo "Dump written to: $DUMP_FILE ($(du -h "$DUMP_FILE" | cut -f1))"
echo "Next: run scripts/restore-neon-dump.sh (works fine on VPN, no internet needed -- it only talks to the local Docker container)."
