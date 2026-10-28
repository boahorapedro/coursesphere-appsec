#!/usr/bin/env bash
# Generates traffic against the API to populate the Grafana dashboard.
#
# Prerequisite: environment up  ->  docker compose up -d --build
# Usage (from the repository root):
#   bash scripts/generate-traffic.sh [seconds] [--with-errors]
#   bash scripts/generate-traffic.sh 120              # 2 min of normal traffic
#   bash scripts/generate-traffic.sh 120 --with-errors  # also sends some 500 errors (C15)
set -u

DURATION="${1:-120}"
WITH_ERRORS=0
if [ "${2:-}" = "--with-errors" ]; then WITH_ERRORS=1; fi

BASE="http://localhost:5000"   # Nginx (load balancer)
AUTH="http://localhost:9099"   # Firebase Auth emulator
H="Content-Type: application/json"
PY=$(command -v python3 || command -v python)

# Create a test user directly in the emulator (bypasses the /users/create rate limit)
EMAIL="traffic-$RANDOM$RANDOM@teste.com"
TOKEN=$(curl -s -X POST "$AUTH/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake" \
  -H "$H" -d "{\"email\":\"$EMAIL\",\"password\":\"Senha123\",\"returnSecureToken\":true}" \
  | $PY -c "import sys,json; print(json.load(sys.stdin).get('idToken',''))" 2> /dev/null)

if [ -z "$TOKEN" ]; then
  echo "Could not get a token (is the environment up? wait ~20 s after docker compose up)."
  exit 1
fi

echo "Generating traffic for ${DURATION}s (500 errors included: $WITH_ERRORS)..."
END=$((SECONDS + DURATION))
N=0
while [ "$SECONDS" -lt "$END" ]; do
  N=$((N + 1))
  curl -s -o /dev/null "$BASE/users/info" -H "Authorization: Bearer $TOKEN"          # 200
  curl -s -o /dev/null "$BASE/users/info"                                            # 401 (no token)
  curl -s -o /dev/null -X POST "$BASE/users/query" -H "$H" -d '{"query":"oi"}'       # 200
  if [ "$WITH_ERRORS" -eq 1 ] && [ $((N % 10)) -eq 0 ]; then
    curl -s -o /dev/null -X POST "$BASE/users/info" -H "$H" -d 'null'                # 500 (C15)
  fi
  sleep 0.3
done

echo "Done: $N iterations. Open http://localhost:3001 (CourseSphere folder)."