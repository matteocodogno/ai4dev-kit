#!/usr/bin/env bash
#
# provision-keys.sh — one virtual key per participant, delivered by Slack DM
#
#   ./provision-keys.sh <gateway-url> <participants.csv>
#
# FACILITATOR TOOL. It needs LITELLM_MASTER_KEY, the admin credential for the
# whole cohort. It lives in ai4dev-infrastructure and must NEVER be shipped in
# the participant kit.
#
# Delivery is a Slack DM by default, sent the moment the key is created, so the
# plaintext key never touches your disk. The CSV is opt-in, for the cases where
# you genuinely need one.
#
# Required:
#   LITELLM_MASTER_KEY    admin credential for the gateway
#   SLACK_BOT_TOKEN       xoxb-… with scopes: chat:write, users:lookupByEmail
#                         (some workspaces also require im:write)
#
# Optional:
#   AI4DEV_DELIVERY       slack (default) | csv | both
#   AI4DEV_BUDGET         per-participant budget, whole course (default 25)
#   AI4DEV_COHORT         cohort label, written into each key's metadata
#   AI4DEV_MODELS         comma-separated roles the key may use. Empty = all.
#   AI4DEV_ON_EXISTING    skip (default) | rotate | fail
#   AI4DEV_DASHBOARD_URL  linked in the message so people can find their traces
#   AI4DEV_TEARDOWN_DATE  when the gateway is destroyed, e.g. "24 ottobre"
#   AI4DEV_DRY_RUN=1      resolve every email against Slack and stop. Creates
#                         nothing, sends nothing. Run this first, every time.

set -euo pipefail
umask 077

GATEWAY_RAW="${1:-}"
CSV="${2:-}"

if [[ -z "$GATEWAY_RAW" || -z "$CSV" ]]; then
  echo "usage: provision-keys.sh <gateway-url> <participants.csv>" >&2
  exit 2
fi
[[ -f "$CSV" ]] || { echo "no such file: $CSV" >&2; exit 2; }
: "${LITELLM_MASTER_KEY:?export it, do not paste it}"

BUDGET="${AI4DEV_BUDGET:-25}"
COHORT="${AI4DEV_COHORT:-unspecified}"
MODELS="${AI4DEV_MODELS:-reviewer,reviewer-fallback,committer,committer-fallback,architect,architect-fallback,tester,tester-fallback}"
ON_EXISTING="${AI4DEV_ON_EXISTING:-skip}"
DELIVERY="${AI4DEV_DELIVERY:-slack}"
DASHBOARD="${AI4DEV_DASHBOARD_URL:-}"
TEARDOWN="${AI4DEV_TEARDOWN_DATE:-}"
DRY_RUN="${AI4DEV_DRY_RUN:-0}"

case "$ON_EXISTING" in skip|rotate|fail) ;; *) echo "AI4DEV_ON_EXISTING must be skip, rotate or fail" >&2; exit 2 ;; esac
case "$DELIVERY"    in slack|csv|both)   ;; *) echo "AI4DEV_DELIVERY must be slack, csv or both" >&2; exit 2 ;; esac

use_slack=0
[[ "$DELIVERY" == "slack" || "$DELIVERY" == "both" ]] && use_slack=1
write_csv=0
[[ "$DELIVERY" == "csv"   || "$DELIVERY" == "both" ]] && write_csv=1

[[ "$use_slack" -eq 1 ]] && : "${SLACK_BOT_TOKEN:?needed for Slack delivery. Set AI4DEV_DELIVERY=csv to skip it.}"

# Key endpoints live at the root, not under /v1.
GATEWAY="${GATEWAY_RAW%/}"; GATEWAY="${GATEWAY%/v1}"; GATEWAY="${GATEWAY%/}"

echo "gateway  : $GATEWAY"
echo "budget   : $BUDGET per participant"
echo "cohort   : $COHORT"
echo "existing : $ON_EXISTING"
echo "delivery : $DELIVERY"
[[ "$DRY_RUN" == "1" ]] && echo "mode     : DRY RUN — nothing will be created or sent"
echo

body_file="$(mktemp -t ai4dev-body.XXXXXX)"
slack_file="$(mktemp -t ai4dev-slack.XXXXXX)"
trap 'rm -f "$body_file" "$slack_file"' EXIT

api() {
  # api <path> <json-body> → echoes HTTP status, body lands in $body_file
  # stdin closed: this runs inside a `while read` loop.
  curl -sS -o "$body_file" -w '%{http_code}' \
    -X POST "$GATEWAY$1" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$2" </dev/null || true
}

slack() {
  # slack <method> <json-body> → response lands in $slack_file, returns 0 if ok:true
  curl -sS -o "$slack_file" \
    -X POST "https://slack.com/api/$1" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$2" </dev/null || true
  jq -e '.ok == true' "$slack_file" >/dev/null 2>&1
}

slack_error() { jq -r '.error // "no response"' "$slack_file" 2>/dev/null || echo "unparseable"; }

# ── read the CSV once, into arrays ───────────────────────────────────────────

names=(); emails=()
while IFS=, read -r n e _rest || [[ -n "${n:-}${e:-}" ]]; do
  n="$(printf '%s' "${n:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  e="$(printf '%s' "${e:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$e" == *"@"* ]] || continue          # skips blanks and a header row
  names+=("$n"); emails+=("$e")
done < "$CSV"

expected="${#names[@]}"
[[ "$expected" -gt 0 ]] || { echo "no participants found in $CSV" >&2; exit 2; }
echo "participants in $CSV: $expected"
echo

# ── preflight 1: Slack, and resolve EVERY email before creating anything ─────
#
# Order matters. Creating keys first and discovering afterwards that three
# emails do not exist in Slack leaves three orphan keys that nobody holds.

slack_ids=()
if [[ "$use_slack" -eq 1 ]]; then
  if ! slack auth.test '{}'; then
    echo "✗ Slack token rejected: $(slack_error)" >&2
    echo "  needs scopes chat:write and users:lookupByEmail" >&2
    exit 1
  fi
  echo "✓ Slack token ok — posting as $(jq -r '.user // "?"' "$slack_file")"

  lookup_failed=0
  for i in "${!emails[@]}"; do
    if slack users.lookupByEmail "$(jq -n --arg e "${emails[$i]}" '{email:$e}')"; then
      slack_ids+=("$(jq -r '.user.id' "$slack_file")")
    else
      printf '  ✗ %-28s %s → %s\n' "${names[$i]}" "${emails[$i]}" "$(slack_error)" >&2
      slack_ids+=("")
      lookup_failed=1
    fi
  done

  if [[ "$lookup_failed" -eq 1 ]]; then
    cat >&2 <<'HINT'

✗ Some emails do not match a Slack account. Nothing has been created.
  Usually: the person has not joined the workspace yet, or their Slack email
  differs from the one in the CSV. Fix the CSV or chase the invite, then re-run.
HINT
    exit 1
  fi
  echo "✓ all $expected emails resolved to Slack accounts"
  echo
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Dry run complete. Everyone is reachable. Re-run without AI4DEV_DRY_RUN to issue."
  exit 0
fi

# ── preflight 2: gateway and master key ──────────────────────────────────────

probe="$(api /key/generate "$(jq -n --arg a "preflight-$$" '{max_budget:0.01, key_alias:$a}')")"
if [[ "$probe" != 2* ]]; then
  echo "✗ gateway preflight failed: HTTP $probe" >&2
  [[ -s "$body_file" ]] && sed 's/^/    /' "$body_file" >&2
  cat >&2 <<'HINT'

  Most likely, in order:
    401 / 403  → LITELLM_MASTER_KEY is unset or wrong
    404        → wrong URL. Key endpoints are at the ROOT, not under /v1
    5xx        → the gateway is up but unhealthy: check the Railway logs
    000/empty  → no HTTP response: DNS, TLS, or the domain is not live
HINT
  exit 1
fi
preflight_key="$(jq -r '.key // empty' "$body_file")"
[[ -n "$preflight_key" ]] || { echo "✗ preflight returned 2xx but no key." >&2; exit 1; }
api /key/delete "$(jq -n --arg k "$preflight_key" '{keys:[$k]}')" >/dev/null
echo "✓ gateway reachable, master key accepted"
echo

# ── issue and deliver ────────────────────────────────────────────────────────

models_json="$(jq -cn --arg m "$MODELS" 'if $m == "" then [] else ($m | split(",")) end')"

out="keys.csv"
undelivered="keys-undelivered.csv"
[[ "$write_csv" -eq 1 ]] && : > "$out"
: > "$undelivered"

issued=0; skipped=0; failed=0; undeliv=0
skipped_names=()

issue_for() {
  api /key/generate "$(jq -n \
    --arg alias "$1" --arg email "$2" --arg cohort "$COHORT" \
    --argjson budget "$BUDGET" --argjson models "$models_json" '
    {
      key_alias: $alias,
      max_budget: $budget,
      budget_duration: "30d",
      metadata: {participant: $alias, email: $email, cohort: $cohort}
    }
    + (if ($models|length) > 0 then {models:$models} else {} end)')"
}

compose_message() {
  # compose_message <first-name> <key>
  local first="$1" key="$2" msg
  msg="Ciao ${first}! 👋

Ecco la tua chiave personale per il gateway AI del corso AI4Dev.

\`\`\`
${key}
\`\`\`

*Cosa farci*, due comandi:
\`\`\`
mkdir -p ~/.config/ai4dev && cp ~/ai4dev-kit/config.example ~/.config/ai4dev/config
chmod 600 ~/.config/ai4dev/config
\`\`\`
Apri quel file, incolla la chiave in \`AI4DEV_API_KEY\` e metti \`AI4DEV_GATEWAY_URL=\"${GATEWAY}/v1\"\`.

Poi lancia \`ai4dev doctor\`. Se è tutto verde sei pronto, e non devi dirmelo: lo vedo io dalla dashboard.

*Tre cose da sapere.*
• La chiave è **tua**: ogni richiesta viene tracciata e attribuita al tuo nome.
• Ha un budget di ${BUDGET} euro per tutto il corso. Finito quello le richieste vengono rifiutate, non rallentate.
• Usala per il codice del corso. Non mandarci codice proprietario della tua azienda: i facilitatori possono leggere tutto quello che passa di qui."

  [[ -n "$DASHBOARD" ]] && msg="${msg}

Le tue tracce: ${DASHBOARD}"

  [[ -n "$TEARDOWN" ]] && msg="${msg}

Il gateway e tutte le tracce vengono distrutti il ${TEARDOWN}."

  msg="${msg}

Questo messaggio resta nel tuo storico Slack. Se ti dà fastidio, cancellalo pure: la chiave ce l'hai già nel file."

  printf '%s' "$msg"
}

for i in "${!names[@]}"; do
  name="${names[$i]}"; email="${emails[$i]}"
  first="${name%% *}"

  code="$(issue_for "$name" "$email")"
  key="$(jq -r '.key // empty' "$body_file" 2>/dev/null || true)"
  msg="$(jq -r '.error.message // .detail // empty' "$body_file" 2>/dev/null || true)"

  # already exists — the normal case on a re-run
  if [[ "$code" != 2* && "$msg" == *"already exists"* ]]; then
    case "$ON_EXISTING" in
      skip)
        printf '  ~ %-28s already has a key, left alone\n' "$name"
        skipped_names+=("$name"); skipped=$((skipped+1)); continue ;;
      fail)
        printf '  ✗ %-28s already has a key\n' "$name" >&2
        failed=$((failed+1)); continue ;;
      rotate)
        api /key/delete "$(jq -n --arg a "$name" '{key_aliases:[$a]}')" >/dev/null
        code="$(issue_for "$name" "$email")"
        key="$(jq -r '.key // empty' "$body_file" 2>/dev/null || true)"
        if [[ "$code" != 2* || -z "$key" ]]; then
          printf '  ✗ %-28s rotation failed, HTTP %s — old key still valid\n' "$name" "$code" >&2
          failed=$((failed+1)); continue
        fi ;;
    esac
  fi

  if [[ "$code" != 2* || -z "$key" ]]; then
    printf '  ✗ %-28s HTTP %s\n' "$name" "$code" >&2
    [[ -n "$msg" ]] && printf '      %s\n' "$msg" >&2
    failed=$((failed+1)); continue
  fi

  [[ "$write_csv" -eq 1 ]] && printf '%s,%s,%s\n' "$name" "$email" "$key" >> "$out"

  if [[ "$use_slack" -eq 1 ]]; then
    if slack chat.postMessage "$(jq -n \
         --arg ch "${slack_ids[$i]}" --arg t "$(compose_message "$first" "$key")" \
         '{channel:$ch, text:$t, unfurl_links:false}')"; then
      printf '  ✓ %-28s key issued, DM sent\n' "$name"
      issued=$((issued+1))
    else
      # The key exists but nobody has it. This must never be silent.
      printf '  ! %-28s key issued but DM FAILED: %s\n' "$name" "$(slack_error)" >&2
      printf '%s,%s,%s\n' "$name" "$email" "$key" >> "$undelivered"
      undeliv=$((undeliv+1)); issued=$((issued+1))
    fi
  else
    printf '  ✓ %-28s %s…\n' "$name" "${key:0:12}"
    issued=$((issued+1))
  fi
done

# ── summary ──────────────────────────────────────────────────────────────────

echo
printf 'issued: %d   skipped: %d   failed: %d   undelivered: %d\n' \
  "$issued" "$skipped" "$failed" "$undeliv"

seen=$((issued + skipped + failed))
if [[ "$seen" -ne "$expected" ]]; then
  printf '\n✗ %d rows in the CSV, %d processed. %d never attempted.\n' \
    "$expected" "$seen" "$((expected - seen))" >&2
  exit 1
fi

if [[ "$skipped" -gt 0 ]]; then
  echo
  echo "Already had a key, untouched:"
  printf '  %s\n' "${skipped_names[@]}"
  echo
  echo "  The gateway never reveals an existing key's value, only its alias, so a"
  echo "  lost key cannot be looked up. Rotate it:"
  echo "    AI4DEV_ON_EXISTING=rotate ./provision-keys.sh <gateway> <csv>"
fi

if [[ "$undeliv" -gt 0 ]]; then
  echo
  echo "✗ $undeliv key(s) were created but the DM did not go out." >&2
  echo "  They are in $undelivered (mode 600). Send them by hand, then delete it." >&2
  echo "  Until you do, those people have a key issued in their name and no way to use it." >&2
  exit 1
fi
rm -f "$undelivered"

if [[ "$issued" -eq 0 ]]; then
  [[ "$write_csv" -eq 1 ]] && rm -f "$out"
  if [[ "$failed" -gt 0 ]]; then
    echo "✗ nothing issued, and $failed row(s) failed." >&2
    exit 1
  fi
  echo
  echo "Nothing new to issue — everyone in the CSV already has a key."
  exit 0
fi

echo
if [[ "$write_csv" -eq 1 ]]; then
  echo "wrote $out (mode 600), $issued key(s). Delete it as soon as you are done."
else
  echo "$issued key(s) delivered by Slack. No plaintext key touched this disk."
fi
[[ "$failed" -gt 0 ]] && exit 1
exit 0