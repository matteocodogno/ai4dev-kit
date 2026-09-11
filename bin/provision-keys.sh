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

# Normalise the gateway URL: strip trailing slashes, and strip a trailing /v1.
# The key endpoints live at the root, not under /v1, and '//key/generate' is a
# 404 on some deployments. This is what bit the first run.
GATEWAY="${GATEWAY_RAW%/}"
GATEWAY="${GATEWAY%/v1}"
GATEWAY="${GATEWAY%/}"

echo "gateway : $GATEWAY"
echo "budget  : $BUDGET per participant"
echo "cohort  : $COHORT"
echo

# ── preflight: is the gateway up, and does the master key work? ───────────────

probe="$(curl -sS -o /tmp/ai4dev-probe.$$ -w '%{http_code}' \
  -X POST "$GATEWAY/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"max_budget":0.01,"key_alias":"preflight-'"$$"'"}' || true)"

if [[ "$probe" != 2* ]]; then
  echo "✗ preflight failed: HTTP $probe" >&2
  if [[ -s /tmp/ai4dev-probe.$$ ]]; then
    echo "  response:" >&2
    sed 's/^/    /' /tmp/ai4dev-probe.$$ >&2
  fi
  rm -f /tmp/ai4dev-probe.$$
  cat >&2 <<'HINT'

  Most likely, in order:
    401 / 403  → LITELLM_MASTER_KEY is unset or wrong
    404        → wrong URL. Key endpoints are at the ROOT, not under /v1
    5xx        → the gateway is up but unhealthy: check the Railway logs
    000/empty  → no HTTP response at all: DNS, TLS or the domain is not live
HINT
  exit 1
fi

preflight_key="$(jq -r '.key // empty' /tmp/ai4dev-probe.$$)"
rm -f /tmp/ai4dev-probe.$$
if [[ -z "$preflight_key" ]]; then
  echo "✗ preflight returned 2xx but no key. The API shape is not what we expect." >&2
  exit 1
fi
curl -sS -X POST "$GATEWAY/key/delete" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg k "$preflight_key" '{keys: [$k]}')" >/dev/null || true
echo "✓ preflight ok — gateway reachable, master key accepted"
echo

# ── issue the keys ───────────────────────────────────────────────────────────

models_json="$(jq -cn --arg m "$MODELS" \
  'if $m == "" then [] else ($m | split(",")) end')"

out="keys.csv"
: > "$out"
issued=0; failed=0

# tr -d '\r' handles CSVs exported from Excel.
while IFS=, read -r name email _rest; do
  name="$(printf '%s' "${name:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  email="$(printf '%s' "${email:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Skips blank lines and a header row in one rule.
  [[ "$email" == *"@"* ]] || continue

  payload="$(jq -n \
    --arg alias "$name" --arg email "$email" --arg cohort "$COHORT" \
    --argjson budget "$BUDGET" --argjson models "$models_json" '
    {
      key_alias: $alias,
      max_budget: $budget,
      budget_duration: "30d",
      metadata: {participant: $alias, email: $email, cohort: $cohort}
    }
    + (if ($models | length) > 0 then {models: $models} else {} end)')"

  code="$(curl -sS -o /tmp/ai4dev-key.$$ -w '%{http_code}' \
    -X POST "$GATEWAY/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"

  key="$(jq -r '.key // empty' /tmp/ai4dev-key.$$ 2>/dev/null || true)"

  if [[ "$code" == 2* && -n "$key" ]]; then
    printf '%s,%s,%s\n' "$name" "$email" "$key" >> "$out"
    printf '  ✓ %-28s %s…\n' "$name" "${key:0:12}"
    issued=$((issued+1))
  else
    printf '  ✗ %-28s HTTP %s\n' "$name" "$code" >&2
    jq -r '.error.message // .detail // .' /tmp/ai4dev-key.$$ 2>/dev/null \
      | head -3 | sed 's/^/      /' >&2 || true
    failed=$((failed+1))
  fi
  rm -f /tmp/ai4dev-key.$$
done < "$CSV"

echo
echo "issued: $issued   failed: $failed"

if [[ "$issued" -eq 0 ]]; then
  echo "✗ no keys were issued. $out is empty." >&2
  rm -f "$out"
  exit 1
fi

echo "wrote $out (mode 600)."
echo "Push it to Infisical, one entry per participant, then: rm $out"
[[ "$failed" -gt 0 ]] && exit 1
exit 0