#!/usr/bin/env bash
# Shared base for local Neon execution scripts.
# Keep runtime configuration and execution results out of version control.

set -euo pipefail
umask 077

neon_require_commands() {
  local command
  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || {
      printf 'missing_command=%s\n' "$command" >&2
      return 1
    }
  done
}

neon_init() {
  IMPROVEMENT_ID="$1"
  EXECUTION_NUMBER="$2"
  SCRIPT_PATH="$(realpath "${BASH_SOURCE[1]}")"
  SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
  CONFIG_FILE="$SCRIPT_DIR/neon-config.json"
  BASE_DIR="$SCRIPT_DIR"
  RUN_NAME="${IMPROVEMENT_ID}-neon-${EXECUTION_NUMBER}-$(date -u +%Y%m%dT%H%M%SZ)"
  WORK_DIR="$BASE_DIR/$RUN_NAME"
  PGPASS_FILE="$(mktemp)"
  STEP="initialization"

  neon_on_error() {
    local status=$?
    printf 'status=failed step=%s exit_code=%s\n' "$STEP" "$status" >&2
    if [[ -d "$WORK_DIR" ]]; then
      printf -- '- status: failed\n- failed_step: %s\n- sensitive_values_recorded: false\n' "$STEP" \
        >"$WORK_DIR/summary.md" 2>/dev/null || true
    fi
    exit "$status"
  }

  trap neon_on_error ERR
  trap 'rm -f "$PGPASS_FILE"; unset NEON_DATABASE_URL PGHOST PGPORT PGUSER PGPASSFILE' EXIT

  neon_require_commands neonctl psql jq python3 git stat
  [[ "$#" -eq 2 ]] || { printf 'neon_init_argument_error=true\n' >&2; return 1; }
  [[ -f "$CONFIG_FILE" ]] || { printf 'missing_neon_config=true\n' >&2; return 1; }
  local config_mode
  config_mode="$(stat -c %a "$CONFIG_FILE" 2>/dev/null || stat -f %Lp "$CONFIG_FILE")"
  [[ "$config_mode" == 600 ]] || { printf 'neon_config_permissions=%s expected=600\n' "$config_mode" >&2; return 1; }
  git check-ignore -q "$CONFIG_FILE" || { printf 'neon_config_not_ignored=true\n' >&2; return 1; }
  PROJECT_ID="$(jq -er '.project_id' "$CONFIG_FILE")"
  BRANCH_ID="$(jq -er '.branch_id' "$CONFIG_FILE")"
  DATABASE="$(jq -er '.database' "$CONFIG_FILE")"
  NEON_DATABASE_URL="$(jq -er '.neon_database_url' "$CONFIG_FILE")"
  git check-ignore -q "$WORK_DIR/.keep" || { printf 'results_directory_not_ignored=true\n' >&2; return 1; }
  mkdir -m 700 "$WORK_DIR"
  printf '# Neon execution summary\n\n- project: %s\n- branch: %s\n- database: %s\n- mutations: none\n- credentials_recorded: false\n- raw_business_data_recorded: false\n' "$PROJECT_ID" "$BRANCH_ID" "$DATABASE" >"$WORK_DIR/summary.md"
}

neon_validate_context() {
  STEP="validate_neon_context"
  printf 'step=validate_neon_context\n'
  printf 'project=%s\nbranch=%s\ndatabase=%s\n' "$PROJECT_ID" "$BRANCH_ID" "$DATABASE"
  neonctl projects get "$PROJECT_ID" --output json >"$WORK_DIR/project.json"
  neonctl branches get "$BRANCH_ID" --project-id "$PROJECT_ID" --output json >"$WORK_DIR/branch.json"
}

neon_validate_connection() {
  STEP="validate_connection"
  case "$NEON_DATABASE_URL" in
    export\ NEON_DATABASE_URL=*) NEON_DATABASE_URL="${NEON_DATABASE_URL#*=}" ;;
    NEON_DATABASE_URL=*) NEON_DATABASE_URL="${NEON_DATABASE_URL#*=}" ;;
  esac
  NEON_DATABASE_URL="$(printf '%s' "$NEON_DATABASE_URL" | sed -E 's/^['"'"']|['"'"']$//g')"
  case "$NEON_DATABASE_URL" in
    postgresql+asyncpg://*) NEON_DATABASE_URL="postgresql://${NEON_DATABASE_URL#*postgresql+asyncpg://}" ;;
    postgresql://*|postgres://*) ;;
    *) printf 'credential_file_format=expected_postgresql_uri_or_assignment\n' >&2; return 1 ;;
  esac
  local uri_database
  uri_database="$(python3 -c 'from urllib.parse import urlsplit; import sys; print((urlsplit(sys.argv[1]).path or "/").lstrip("/"))' "$NEON_DATABASE_URL")"
  [[ "$uri_database" == "$DATABASE" ]] || {
    printf 'database_mismatch=config:%s connection_string:%s\n' "$DATABASE" "$uri_database" >&2
    return 1
  }
}

neon_prepare_pgpass() {
  STEP="prepare_pgpass"
  printf 'step=prepare_pgpass\n'
  python3 - "$NEON_DATABASE_URL" "$PGPASS_FILE" <<'PY'
from pathlib import Path
from urllib.parse import unquote, urlsplit
import os
import sys

url = urlsplit(sys.argv[1])
out = Path(sys.argv[2])
if url.scheme not in {"postgres", "postgresql"} or not url.hostname or not url.username:
    raise SystemExit("connection string is not a supported PostgreSQL URL")
password = unquote(url.password or "")
if not password:
    raise SystemExit("connection string has no password")
def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(":", "\\:")
out.write_text(":".join([
    escape(url.hostname), str(url.port or 5432),
    escape((url.path or "/").lstrip("/") or "*"),
    escape(unquote(url.username)), escape(password),
]) + "\n")
os.chmod(out, 0o600)
PY
  export PGPASSFILE="$PGPASS_FILE"
  export PGDATABASE="$DATABASE"
  export PGSSLMODE=require
  export PGHOST="$(python3 -c 'from urllib.parse import urlsplit; import sys; print(urlsplit(sys.argv[1]).hostname)' "$NEON_DATABASE_URL")"
  export PGPORT="$(python3 -c 'from urllib.parse import urlsplit; import sys; print(urlsplit(sys.argv[1]).port or 5432)' "$NEON_DATABASE_URL")"
  export PGUSER="$(python3 -c 'from urllib.parse import urlsplit,unquote; import sys; print(unquote(urlsplit(sys.argv[1]).username))' "$NEON_DATABASE_URL")"
}

neon_run_readonly() {
  local name="$1" query="$2"
  STEP="query_${name}"
  printf 'step=%s\n' "$STEP"
  psql --dbname="$DATABASE" --no-password --no-psqlrc --no-align --field-separator=',' \
    --set=ON_ERROR_STOP=1 --set=statement_timeout=30000 \
    --command="BEGIN READ ONLY; SET LOCAL statement_timeout='30000'; ${query}; COMMIT;" \
    >"$WORK_DIR/$name.csv"
}

neon_summary_line() {
  printf '%s\n' "$1" >>"$WORK_DIR/summary.md"
}
