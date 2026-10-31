#!/usr/bin/env bash
# One-time setup of the hosted Supabase project. Safe to run again.
#
#   brew install supabase/tap/supabase
#   supabase login                       # opens the browser
#   supabase/setup.sh <project-ref>      # the ref is in the dashboard URL: /project/<ref>
#
# It links the project, applies the migrations, turns on anonymous sign-ins, deploys both Edge
# Functions, stores what the media trigger needs in Vault, writes the URL and anon key into
# ios/Config/Local.xcconfig and web/app/.env.local, and uploads the stock tracks if
# supabase/stock-music/ holds them (warm_piano.m4a, bright_strings.m4a, reflective_guitar.m4a,
# triumphant_brass.m4a). Linking asks for the database password you chose for the project.
set -euo pipefail

ref="${1:?usage: supabase/setup.sh <project-ref>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
url="https://$ref.supabase.co"

step() { printf '\n== %s\n' "$1"; }

step "Link"
supabase link --project-ref "$ref"

step "Migrations"
supabase db push --linked --yes

step "Auth settings (supabase/config.toml)"
supabase config push --project-ref "$ref" --yes

step "Edge Functions"
supabase functions deploy sign-media --project-ref "$ref" --no-verify-jwt --use-api
supabase functions deploy process-media --project-ref "$ref" --use-api

step "Keys"
keys="$(supabase projects api-keys --project-ref "$ref" --reveal -o json)"
key_named() { jq -r --arg n "$1" 'map(select(.name == $n)) | first | .api_key // empty' <<<"$keys"; }
anon="$(key_named anon)"
service="$(key_named service_role)"
if [ -z "$anon" ] || [ -z "$service" ]; then
  echo "Could not read the anon and service_role keys. Enable the legacy API keys under" >&2
  echo "Project Settings > API Keys, then run this again." >&2
  exit 1
fi

step "Media trigger secrets (Vault)"
sql="$(mktemp)"
trap 'rm -f "$sql"' EXIT
chmod 600 "$sql"
cat >"$sql" <<SQL
delete from vault.secrets where name in ('sendoff_project_url', 'sendoff_service_role_key');
select vault.create_secret('$url', 'sendoff_project_url');
select vault.create_secret('$service', 'sendoff_service_role_key');
SQL
supabase db query --linked -f "$sql" >/dev/null
echo "stored"

step "Client config"
xc=ios/Config/Local.xcconfig
[ -f "$xc" ] || cp ios/Config/Local.xcconfig.example "$xc"
host="${url#https://}"
sed -i.bak \
  -e "s#^SUPABASE_URL = .*#SUPABASE_URL = https:/\$()/$host#" \
  -e "s#^SUPABASE_ANON_KEY *=.*#SUPABASE_ANON_KEY = $anon#" \
  -e "s#^MUSIC_BASE_URL = .*#MUSIC_BASE_URL = https:/\$()/$host/storage/v1/object/public/stock-music#" \
  "$xc" && rm -f "$xc.bak"
echo "wrote $xc"
cat >web/app/.env.local <<ENV
VITE_SUPABASE_URL=$url
VITE_SUPABASE_ANON_KEY=$anon
VITE_PUBLIC_ORIGIN=https://sendoffapp.com
ENV
echo "wrote web/app/.env.local"

step "Stock music"
shopt -s nullglob
tracks=(supabase/stock-music/*.m4a)
if [ ${#tracks[@]} -eq 0 ]; then
  echo "supabase/stock-music/ is empty; skipped. Add the four .m4a files and run this again."
else
  for f in "${tracks[@]}"; do
    supabase storage cp "$f" "ss:///stock-music/$(basename "$f")" --linked --experimental \
      --content-type audio/mp4 --cache-control "max-age=31536000"
  done
fi

printf '\nDone. Rebuild the iOS app (it now talks to %s) and restart the web dev server.\n' "$url"
