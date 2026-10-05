#!/usr/bin/env bash
# Petite bibliothèque de vérification : appels HTTP + assertions sur le JSON.
# Dépendances : curl, python3. Rien d'autre.

API="${API:-http://localhost:${API_PORT:-5199}}"
PASS=0; FAIL=0
BODY=""; STATUS=""

vert()  { printf '\033[32m%s\033[0m\n' "$*"; }
rouge() { printf '\033[31m%s\033[0m\n' "$*"; }
titre() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# http METHODE CHEMIN [CORPS_JSON] → remplit $STATUS et $BODY
http() {
  local method="$1" path="$2" data="${3:-}" out
  if [ -n "$data" ]; then
    out=$(curl -s -g -w $'\n%{http_code}' -X "$method" -H 'Content-Type: application/json' -d "$data" "$API$path")
  else
    out=$(curl -s -g -w $'\n%{http_code}' -X "$method" "$API$path")
  fi
  STATUS="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

# check "libellé" 'expression python'  — `j` = corps JSON décodé, `s` = statut HTTP, `b` = corps brut
check() {
  local label="$1" expr="$2"
  if BODY="$BODY" STATUS="$STATUS" python3 -c '
import json, os, sys
b = os.environ["BODY"]; s = int(os.environ["STATUS"] or 0)
try: j = json.loads(b)
except Exception: j = None
sys.exit(0 if eval(sys.argv[1]) else 1)' "$expr" 2>/dev/null; then
    PASS=$((PASS+1)); vert "  ✔ $label"
  else
    FAIL=$((FAIL+1)); rouge "  ✘ $label"
    printf '      HTTP %s — %s\n' "$STATUS" "$(printf '%s' "$BODY" | head -c 400)"
  fi
}

# Les noms de conteneurs (pixelhub-postgres…) sont fixes, comme dans les supports :
# un seul snapshot peut tourner à la fois. On refuse de démarrer si un autre projet les occupe.
guard_conflicts() {
  local mine other
  mine="$(docker compose config --format json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')"
  other=$(docker ps -a --filter 'name=^pixelhub-' --format '{{.Label "com.docker.compose.project"}}' | sort -u | grep -vx "$mine" || true)
  if [ -n "$other" ]; then
    rouge "Des conteneurs pixelhub-* appartiennent déjà à un autre projet : $other"
    echo  "Arrêtez-les d'abord :  docker compose -p <projet> --profile app down"
    exit 2
  fi
}

wait_api() {
  printf 'Attente de l’API sur %s ' "$API"
  for _ in $(seq 1 90); do
    if curl -sf "$API/" > /dev/null; then echo; vert "API prête."; return 0; fi
    printf '.'; sleep 2
  done
  echo; rouge "L'API ne répond pas après 180 s."; docker compose --profile app logs --tail 40 api; exit 1
}

# Démarrage standard d'une vérification : reset (sauf --no-reset), build, attente.
start_stack() {
  cd "$(dirname "$0")/.." || exit 1
  guard_conflicts
  if [[ " $* " != *" --no-reset "* ]]; then
    titre "Remise à zéro de CE snapshot (docker compose down -v : ses volumes seulement)"
    docker compose --profile app down -v --remove-orphans > /dev/null 2>&1
  fi
  titre "Build et démarrage (moteurs + jeux de données + API)"
  docker compose --profile app up -d --build || exit 1
  wait_api
}

finish() {
  echo
  if [ "$FAIL" -eq 0 ]; then vert "RÉSULTAT : $PASS vérifications OK"; else rouge "RÉSULTAT : $FAIL échec(s), $PASS OK"; fi
  if [[ " $* " == *" --down "* ]]; then docker compose --profile app down > /dev/null 2>&1; fi
  [ "$FAIL" -eq 0 ]
}
