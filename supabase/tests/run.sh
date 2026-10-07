#!/usr/bin/env bash
# Runs the migrations and the rules test against a throwaway local Postgres.
# Needs postgresql 16 binaries (brew install postgresql@16 / apt install postgresql-16).
# Usage: supabase/tests/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bin="${PGBIN:-$(dirname "$(command -v pg_ctl 2>/dev/null || ls /usr/lib/postgresql/*/bin/pg_ctl | tail -1)")}"
work="$(mktemp -d)"
port="${PGPORT_TEST:-54329}"
cleanup() { "$bin/pg_ctl" -D "$work/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT

run_as_pg() {
  # initdb refuses to run as root; hop to the postgres user when needed.
  if [ "$(id -u)" = "0" ] && id postgres >/dev/null 2>&1; then
    chown -R postgres "$work"; runuser -u postgres -- "$@"
  else
    "$@"
  fi
}

run_as_pg "$bin/initdb" -D "$work/data" -A trust -U postgres >/dev/null
run_as_pg "$bin/pg_ctl" -D "$work/data" -o "-p $port -k $work -c listen_addresses=''" -w start >/dev/null
export PGHOST="$work" PGPORT="$port" PGUSER=postgres PGDATABASE=postgres

psql -v ON_ERROR_STOP=1 -q -f "$here/stubs.sql"
for m in "$root"/supabase/migrations/*.sql; do
  echo "applying $(basename "$m")"
  psql -v ON_ERROR_STOP=1 -q -f "$m"
done
psql -v ON_ERROR_STOP=1 -f "$here/rules_test.sql"
