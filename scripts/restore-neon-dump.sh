#!/usr/bin/env bash
# ============================================================================
# restore-neon-dump.sh - load a Neon dump into the local Postgres container
#
# Safe to run on the Corporative VPN: it only talks to the local Docker/nerdctl
# container (postgres:16 from docker-compose.yml), no internet access needed.
#
# Requires the local DB container already running (make db-up / local-up).
# Requires secrets/neon_dump.sql to exist (produced by export-neon-dump.sh).
#
# DESTRUCTIVE: drops and recreates the entire "public" schema in the local
# "pf_db" database before loading Neon's data (see below for why -- pg_dump's
# own --clean/--if-exists drop statements don't always respect FK dependency
# order). Local-only throwaway DB by design (docker-compose "postgres_data"
# volume) -- if you need to keep what's there, back it up first.
#
# Plain SQL replay via psql (not pg_restore) on purpose: the dump is
# generated with pg_dump --format=plain to sidestep custom-format archive
# version mismatches between the host's pg_dump and this container's older
# Postgres client tools. See export-neon-dump.sh for the full explanation.
#
# Usage:
#   scripts/restore-neon-dump.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DUMP_FILE="$ROOT_DIR/secrets/neon_dump.sql"

DB_USER="pf_db"
DB_NAME="pf_db"

# Same auto-detect logic as the Makefile: prefer nerdctl (Rancher Desktop) over docker.
NERDCTL_BIN="$(
  if nerdctl info >/dev/null 2>&1; then
    echo nerdctl
  elif "$HOME/.rd/bin/nerdctl" info >/dev/null 2>&1; then
    echo "$HOME/.rd/bin/nerdctl"
  elif "$HOME/.rd/bin/nerdctl" --address /var/run/docker/containerd/containerd.sock info >/dev/null 2>&1; then
    echo "$HOME/.rd/bin/nerdctl --address /var/run/docker/containerd/containerd.sock"
  else
    echo docker
  fi
)"

if [ ! -f "$DUMP_FILE" ]; then
  echo "ERROR: missing $DUMP_FILE"
  echo "Run scripts/export-neon-dump.sh first (off the Corporative VPN)."
  exit 1
fi

cd "$ROOT_DIR"
if ! $NERDCTL_BIN compose exec -T db pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
  echo "ERROR: local db container is not up. Run 'make db-up' (or 'make local-up') first."
  exit 1
fi

echo "Resetting local schema (avoids fighting pg_dump --clean's drop ordering)..."
# The dump's own DROP ... IF EXISTS statements can fail on FK dependency
# order in some cases. Simplest robust fix: start from a truly empty
# schema so every DROP IF EXISTS in the dump becomes a harmless no-op.
$NERDCTL_BIN compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -c \
  'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO '"$DB_USER"';'

echo "Restoring $(du -h "$DUMP_FILE" | cut -f1) dump into local db..."
# Strip session-config lines that only exist on newer Postgres than this
# container's (e.g. "transaction_timeout" was added in PG17; the container
# runs postgres:16). Safe to drop -- they only affect the dump/restore
# session itself, not the resulting schema or data.
sed '/^SET transaction_timeout/d' "$DUMP_FILE" \
  | $NERDCTL_BIN compose exec -T db psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -f /dev/stdin

echo ""
echo "Restore complete. Quick sanity check:"
$NERDCTL_BIN compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT 'PAY_EMPLOYER' AS table_name, count(*) FROM \"PAY_EMPLOYER\"
   UNION ALL SELECT 'PAY_PENS_PLAN', count(*) FROM \"PAY_PENS_PLAN\"
   UNION ALL SELECT 'RAT_CURRENCY', count(*) FROM \"RAT_CURRENCY\";"
