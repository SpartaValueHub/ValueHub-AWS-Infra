#!/usr/bin/env bash
set -euo pipefail
cd /opt/valuehub-aws-infra

# apps .env
cat > .env <<'EOF'
IMAGE_TAG=dev
MYSQL_HOST=172.31.8.143
MYSQL_USER=root
MYSQL_ROOT_PASSWORD=root1234
MONGODB_HOST=172.31.8.143
MONGODB_USERNAME=admin
MONGODB_PASSWORD=admin1234
MONGODB_DATABASE=chatting_db
MONGODB_REPLICA_SET=rs0
SECURITY_JWT_ENABLED=true
AUTH_COOKIE_ACCESS_NAME=vh_access_token
JWT_ACCESS_TOKEN_MINUTES=15
JWT_REFRESH_TOKEN_DAYS=30
AUTH_ALLOWED_ORIGINS=http://localhost:3000,https://localhost:3000
PORTONE_API_SECRET=
CI_HASH_KEY=
CAPTCHA_ENABLED=false
RECAPTCHA_SECRET_KEY=
EOF

mkdir -p secrets
if [ ! -f secrets/jwt-private.pem ] || [ ! -f secrets/jwt-public.pem ]; then
  openssl genrsa -out secrets/jwt-private.pem 2048
  openssl rsa -in secrets/jwt-private.pem -pubout -out secrets/jwt-public.pem
  chmod 600 secrets/jwt-private.pem
  chmod 644 secrets/jwt-public.pem
  echo "JWT keypair generated"
fi

docker compose -f compose.prod-apps.yml --env-file /opt/valuehub-aws-infra/.env pull
docker compose -f compose.prod-apps.yml --env-file /opt/valuehub-aws-infra/.env up -d --remove-orphans
sleep 20
docker compose -f compose.prod-apps.yml --env-file /opt/valuehub-aws-infra/.env ps
