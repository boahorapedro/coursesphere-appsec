#!/bin/sh
set -e

# Trava de escopo: sem os emuladores, o SDK falaria com o Firebase real.
: "${FIREBASE_AUTH_EMULATOR_HOST:?defina FIREBASE_AUTH_EMULATOR_HOST: este ambiente só roda contra o emulador}"
: "${FIREBASE_DATABASE_EMULATOR_HOST:?defina FIREBASE_DATABASE_EMULATOR_HOST: este ambiente só roda contra o emulador}"

# Credencial descartável: chave RSA gerada agora, sem valor fora deste container.
if [ ! -f credentials.json ]; then
python - <<'PY'
import json
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
pem = key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()
json.dump({
    "type": "service_account", "project_id": "demo-coursesphere",
    "private_key_id": "0" * 40, "private_key": pem,
    "client_email": "teste@demo-coursesphere.iam.gserviceaccount.com",
    "client_id": "0", "token_uri": "https://oauth2.googleapis.com/token",
}, open("credentials.json", "w"))
PY
fi

# Chave da OpenAI fictícia: o QueryManager é um stub e não chama a API.
[ -f config.json ] || echo '{"openai_api_key":"sk-dummy-local-only"}' > config.json

exec "$@"