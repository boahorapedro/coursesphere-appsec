#!/usr/bin/env bash
# CourseSphere smoke and security regression tests.
# Verifies the fixes (C04, C05, C19), the hardenings (C06, C12), the Nginx load
# balancing, and observability. Runs against the local environment.
#
# Prerequisite: environment running -> docker compose up -d --build
# Usage (at the repository root):   bash scripts/smoke-test.sh
set -u
cd "$(dirname "$0")/.." || exit 2

BASE="http://localhost:5000"     # Nginx 
AUTH="http://localhost:9099"     # Firebase Auth emulator
H="Content-Type: application/json"
PY=$(command -v python3 || command -v python)
PASS=0
FAIL=0

ok()   { echo "  [OK]    $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FALHA] $1"; FAIL=$((FAIL + 1)); }
check() {  
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (esperado: $2, obtido: $3)"; fi
}
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

wait_ok() {  # wait for URL to respond with 2xx
  local i=0
  until curl -sf -o /dev/null --max-time 2 "$1"; do
    i=$((i + 1))
    if [ "$i" -ge "$2" ]; then echo "Tempo esgotado esperando $1"; exit 2; fi
    sleep 1
  done
}
wait_up() {  # wait for any HTTP response (port is up)
  local i=0
  until curl -s -o /dev/null --max-time 2 "$1"; do
    i=$((i + 1))
    if [ "$i" -ge "$2" ]; then echo "Tempo esgotado esperando $1"; exit 2; fi
    sleep 1
  done
}

echo "Preparando: reiniciando o Nginx (zera os contadores de rate limit e relê os IPs das réplicas)"
docker compose restart nginx > /dev/null 2>&1
wait_ok "$BASE/health" 120
wait_up "$AUTH/" 180
wait_up "http://localhost:9000/" 180

echo
echo "== Disponibilidade e cabeçalhos"
check "/health responde 200" 200 "$(code "$BASE/health")"
check "/metrics NÃO é público (bloqueado no Nginx)" 404 "$(code "$BASE/metrics")"
HDRS=$(curl -s -D - -o /dev/null "$BASE/health" | tr -d '\r')
if echo "$HDRS" | grep -qi '^X-Content-Type-Options: nosniff$'; then ok "cabeçalho X-Content-Type-Options presente"; else fail "cabeçalho X-Content-Type-Options ausente"; fi
if echo "$HDRS" | grep -qiE '^Server: nginx$'; then ok "versão do Nginx oculta"; else fail "o cabeçalho Server expõe a versão do Nginx"; fi

echo
echo "== C04: token somente no cabeçalho Authorization"
EMAIL="smoke-$RANDOM$RANDOM@teste.com"
TOKEN=$(curl -s -X POST "$AUTH/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake" \
  -H "$H" -d "{\"email\":\"$EMAIL\",\"password\":\"Senha123\",\"returnSecureToken\":true}" \
  | $PY -c "import sys,json; print(json.load(sys.stdin).get('idToken',''))" 2> /dev/null)
if [ -n "$TOKEN" ]; then ok "token de teste obtido no emulador"; else fail "não foi possível obter token no emulador"; fi
check "token no cabeçalho é aceito" 200 "$(code "$BASE/users/info" -H "Authorization: Bearer $TOKEN")"
check "token na query string é recusado" 401 "$(code "$BASE/users/info?id_token=$TOKEN")"
check "sem token a rota recusa" 401 "$(code "$BASE/users/info")"

echo
echo "== Observabilidade"
LOGS=$(docker compose logs backend --no-log-prefix 2> /dev/null)
if echo "$LOGS" | grep -q 'id_token='; then fail "o log do backend contém 'id_token='"; else ok "nenhum token aparece nos logs do backend"; fi
LAST=$(echo "$LOGS" | grep '"message": "request"' | tail -1)
if echo "$LAST" | $PY -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'status' in d and 'request_id' in d and 'route' in d" 2> /dev/null; then
  ok "logs em JSON com status, rota e request_id"
else
  fail "a última linha de log de requisição não é um JSON válido com os campos esperados"
fi
if docker compose exec -T backend python -c "import urllib.request as u; print(u.urlopen('http://localhost:5000/metrics').read().decode())" 2> /dev/null | grep -q '^http_requests_total'; then
  ok "/metrics (rede interna) expõe http_requests_total"
else
  fail "/metrics interno não expõe http_requests_total"
fi

echo
echo "== Balanceamento entre as réplicas (Nginx)"
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for _ in $(seq 1 20); do curl -s -o /dev/null "$BASE/users/info"; sleep 0.1; done
REPLICAS=$(docker compose logs backend --since "$SINCE" 2> /dev/null | grep '"path": "/users/info"' | cut -d'|' -f1 | sort -u | wc -l | tr -d ' ')
check "as 2 réplicas receberam requisições" 2 "$REPLICAS"

echo
echo "== C19: resposta uniforme no cadastro"
CE="c19-$RANDOM$RANDOM@teste.com"
BODY="{\"email\":\"$CE\",\"password\":\"Senha123\"}"
R1=$(curl -s -w "|%{http_code}" -X POST "$BASE/users/create" -H "$H" -d "$BODY")
R2=$(curl -s -w "|%{http_code}" -X POST "$BASE/users/create" -H "$H" -d "$BODY")
check "cadastro aceito (200)" 200 "${R1##*|}"
check "1º e 2º cadastro do mesmo e-mail têm resposta idêntica" "$R1" "$R2"
if echo "$R1" | grep -q 'user_id'; then fail "a resposta de cadastro expõe user_id"; else ok "a resposta de cadastro não expõe user_id"; fi

echo
echo "== C06: rate limit em /users/create"
N429=0
for i in $(seq 1 10); do
  c=$(code -X POST "$BASE/users/create" -H "$H" -d "{\"email\":\"rl-$i-$RANDOM@teste.com\",\"password\":\"Senha123\"}")
  if [ "$c" = "429" ]; then N429=$((N429 + 1)); fi
done
if [ "$N429" -ge 1 ]; then ok "rate limit ativo ($N429 de 10 requisições recusadas com 429)"; else fail "nenhuma das 10 requisições foi recusada com 429"; fi

echo
echo "== C12: containers sem root"
for s in backend frontend; do
  uid=$(docker compose exec -T "$s" id -u 2> /dev/null | tr -d '\r')
  if [ -n "$uid" ] && [ "$uid" != "0" ]; then ok "$s roda como uid $uid"; else fail "$s roda como root ou não respondeu"; fi
done

echo
echo "== C05: credenciais do Reddit fora do código atual"
if git ls-files --error-unmatch backend/cornell-course-sphere-data/reddit-data/reddit_key.json > /dev/null 2>&1; then
  fail "reddit_key.json ainda está versionado"
else
  ok "reddit_key.json não está versionado"
fi

echo
echo "Resultado: $PASS verificações OK, $FAIL falhas"
[ "$FAIL" -eq 0 ]