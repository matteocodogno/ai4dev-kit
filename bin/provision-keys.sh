#!/usr/bin/env bash
#
# provision-keys.sh — one virtual key per participant, from a CSV of "name,email"
#
#   ./provision-keys.sh <gateway-url> <participants.csv>
#
# FACILITATOR TOOL. It needs LITELLM_MASTER_KEY, which is the admin credential
# for the whole cohort. It must live in ai4dev-infrastructure and must NEVER be
# shipped in the participant kit.
#
# Environment:
#   LITELLM_MASTER_KEY   required. Export it from your secret manager.
#   AI4DEV_BUDGET        per-participant budget for the whole course (default 25)
#   AI4DEV_COHORT        cohort label written into each key's metadata
#   AI4DEV_MODELS        comma-separated roles the key may use. Empty = all.
#                        Leave empty while debugging: a role that does not exist
#                        in the gateway config makes key creation fail.
#   AI4DEV_ON_EXISTING   skip (default) | rotate | fail
#                        What to do when that alias already has a key.
#                          skip   → leave it alone, report it, carry on
#                          rotate → delete the old one, issue a new one
#                          fail   → count it as an error
#
# Re-running this script is expected and safe: it is how you add the person who
# joined late. Rows that already have a key are skipped, not failed.

set -euo pipefail
umask 077                      # keys.csv is readable only by you

GATEWAY_RAW="${1:-}"
CSV="${2:-}"

if [[ -z "$GATEWAY_RAW" || -z "$CSV" ]]; then
  echo "usage: provision-keys.sh <gateway-url> <participants.csv>" >&2
  exit 2
fi
[[ -f "$CSV" ]] || { echo "no such file: $CSV" >&2; exit 2; }
: "${LITELLM_MASTER_KEY:?export it from your secret manager, do not paste it}"

BUDGET="${AI4DEV_BUDGET:-25}"
COHORT="${AI4DEV_COHORT:-unspecified}"
MODELS="${AI4DEV_MODELS:-reviewer,reviewer-fallback,committer,committer-fallback,architect,architect-fallback,tester,tester-fallback}"
ON_EXISTING="${AI4DEV_ON_EXISTING:-skip}"

case "$ON_EXISTING" in
  skip|rotate|fail) ;;
  *) echo "AI4DEV_ON_EXISTING must be skip, rotate or fail" >&2; exit 2 ;;
esac

# Normalise the gateway URL: strip trailing slashes, and strip a trailing /v1.
# The key endpoints live at the root, not under /v1, and '//key/generate' is a
# 404 on some deployments.
GATEWAY="${GATEWAY_RAW%/}"
GATEWAY="${GATEWAY%/v1}"
GATEWAY="${GATEWAY%/}"

echo "gateway : $GATEWAY"
echo "budget  : $BUDGET per participant"
echo "cohort  : $COHORT"
echo "existing: $ON_EXISTING"
echo

body_file="$(mktemp -t ai4dev-key.XXXXXX)"
trap 'rm -f "$body_file"' EXIT

api() {
  # api <path> <json-body> → echoes the HTTP status, body lands in $body_file
  # stdin is closed on purpose: this runs inside a `while read` loop, and a
  # child that reads stdin would eat the rest of the CSV.
  curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$GATEWAY$1" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$2" </dev/null || true
}

# ── preflight: is the gateway up, and does the master key work? ───────────────

probe="$(api /key/generate "$(jq -n --arg a "preflight-$$" '{max_budget:0.01, key_alias:$a}')")"

if [[ "$probe" != 2* ]]; then
  echo "✗ preflight failed: HTTP $probe" >&2
  if [[ -s "$body_file" ]]; then
    echo "  response:" >&2
    sed 's/^/    /' "$body_file" >&2
  fi
  cat >&2 <<'HINT'

  Most likely, in order:
    401 / 403  → LITELLM_MASTER_KEY is unset or wrong
    404        → wrong URL. Key endpoints are at the ROOT, not under /v1
    5xx        → the gateway is up but unhealthy: check the Railway logs
    000/empty  → no HTTP response at all: DNS, TLS or the domain is not live
HINT
  exit 1
fi

preflight_key="$(jq -r '.key // empty' "$body_file")"
if [[ -z "$preflight_key" ]]; then
  echo "✗ preflight returned 2xx but no key. The API shape is not what we expect." >&2
  exit 1
fi
api /key/delete "$(jq -n --arg k "$preflight_key" '{keys: [$k]}')" >/dev/null
echo "✓ preflight ok — gateway reachable, master key accepted"
echo

# ── issue the keys ───────────────────────────────────────────────────────────

models_json="$(jq -cn --arg m "$MODELS" \
  'if $m == "" then [] else ($m | split(",")) end')"

out="keys.csv"
: > "$out"
issued=0; skipped=0; failed=0
skipped_names=()

# How many data rows the CSV actually holds. Counted up front so that a row
# silently lost to a parsing quirk is caught by the reconciliation at the end
# instead of going unnoticed.
expected="$(tr -d '\r' < "$CSV" | grep -c '@' || true)"
echo "participants in $CSV: $expected"
echo

issue_for() {
  # issue_for <name> <email> → echoes the HTTP status
  api /key/generate "$(jq -n \
    --arg alias "$1" --arg email "$2" --arg cohort "$COHORT" \
    --argjson budget "$BUDGET" --argjson models "$models_json" '
    {
      key_alias: $alias,
      max_budget: $budget,
      budget_duration: "30d",
      metadata: {participant: $alias, email: $email, cohort: $cohort}
    }
    + (if ($models | length) > 0 then {models: $models} else {} end)')"
}

# tr -d '\r' handles CSVs exported from Excel.
#
# The `|| [[ -n ... ]]` is not decoration. `read` returns non-zero when it hits
# end of file without a final newline, so a CSV whose last line has no trailing
# newline — which is what most editors produce — silently loses that last
# participant. Without this, the person you just added is the one who never
# gets a key.
while IFS=, read -r name email _rest || [[ -n "${name:-}${email:-}" ]]; do
  name="$(printf '%s' "${name:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  email="$(printf '%s' "${email:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Skips blank lines and a header row in one rule.
  [[ "$email" == *"@"* ]] || continue

  code="$(issue_for "$name" "$email")"
  key="$(jq -r '.key // empty' "$body_file" 2>/dev/null || true)"
  msg="$(jq -r '.error.message // .detail // empty' "$body_file" 2>/dev/null || true)"

  # ── the alias already has a key ───────────────────────────────────────────
  # Not an error. This is what happens on every re-run of a cohort that is
  # already partly provisioned.
  if [[ "$code" != 2* && "$msg" == *"already exists"* ]]; then
    case "$ON_EXISTING" in
      skip)
        printf '  ~ %-28s already has a key, left alone\n' "$name"
        skipped_names+=("$name")
        skipped=$((skipped+1))
        continue ;;
      fail)
        printf '  ✗ %-28s already has a key\n' "$name" >&2
        failed=$((failed+1))
        continue ;;
      rotate)
        api /key/delete "$(jq -n --arg a "$name" '{key_aliases: [$a]}')" >/dev/null
        code="$(issue_for "$name" "$email")"
        key="$(jq -r '.key // empty' "$body_file" 2>/dev/null || true)"
        msg="$(jq -r '.error.message // .detail // empty' "$body_file" 2>/dev/null || true)"
        if [[ "$code" != 2* ]]; then
          printf '  ✗ %-28s rotation failed, HTTP %s\n' "$name" "$code" >&2
          [[ -n "$msg" ]] && printf '      %s\n' "$msg" >&2
          printf '      the old key is still valid. Delete it in the admin UI, then re-run.\n' >&2
          failed=$((failed+1))
          continue
        fi
        printf '  ↻ %-28s rotated, %s…\n' "$name" "${key:0:12}"
        printf '%s,%s,%s\n' "$name" "$email" "$key" >> "$out"
        issued=$((issued+1))
        continue ;;
    esac
  fi

  # ── normal outcome ────────────────────────────────────────────────────────
  if [[ "$code" == 2* && -n "$key" ]]; then
    printf '%s,%s,%s\n' "$name" "$email" "$key" >> "$out"
    printf '  ✓ %-28s %s…\n' "$name" "${key:0:12}"
    issued=$((issued+1))
  else
    printf '  ✗ %-28s HTTP %s\n' "$name" "$code" >&2
    [[ -n "$msg" ]] && printf '      %s\n' "$msg" >&2
    failed=$((failed+1))
  fi
done < "$CSV"

# ── summary ──────────────────────────────────────────────────────────────────

echo
printf 'issued: %d   skipped: %d   failed: %d\n' "$issued" "$skipped" "$failed"

seen=$((issued + skipped + failed))
if [[ "$seen" -ne "$expected" ]]; then
  printf '\n✗ %d rows in the CSV, %d processed. %d row(s) were never attempted.\n' \
    "$expected" "$seen" "$((expected - seen))" >&2
  echo "  Check the CSV for stray quoting, an extra comma, or an odd encoding." >&2
  echo "  Nobody is quietly left without a key on my watch." >&2
  exit 1
fi

if [[ "$skipped" -gt 0 ]]; then
  echo
  echo "Already had a key, untouched:"
  printf '  %s\n' "${skipped_names[@]}"
  cat <<'NOTE'

  Their keys still work and their spend history is intact. The gateway will not
  show you the value of an existing key, only its alias, so if someone has lost
  theirs you cannot look it up. Rotate it:

    AI4DEV_ON_EXISTING=rotate ./provision-keys.sh <gateway> <csv>

  Rotation deletes the old key and issues a new one under the same alias. The
  person must fetch the new value from the secret manager, and anything still
  using the old one stops working.
NOTE
fi

if [[ "$issued" -eq 0 ]]; then
  rm -f "$out"
  if [[ "$failed" -gt 0 ]]; then
    echo "✗ nothing issued, and $failed row(s) failed." >&2
    exit 1
  fi
  echo
  echo "Nothing new to issue — everyone in the CSV already has a key."
  exit 0
fi

echo
echo "wrote $out (mode 600), $issued key(s)."
echo "Push it to Infisical, one entry per participant, then delete the file."
[[ "$failed" -gt 0 ]] && exit 1
exit 0