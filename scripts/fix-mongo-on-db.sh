#!/usr/bin/env bash
set -euo pipefail
cd /opt/valuehub-aws-infra
test -f .env
docker rm -f valuehub-mongo valuehub-mongo-setup valuehub-mongo-keyfile-init 2>/dev/null || true
docker volume rm valuehub-aws-infra_mongo-data valuehub-aws-infra_mongo-keyfile 2>/dev/null || true
docker compose -f compose.prod-db.yml --env-file /opt/valuehub-aws-infra/.env up -d
sleep 30
docker compose -f compose.prod-db.yml --env-file /opt/valuehub-aws-infra/.env ps
echo '==== mongo logs ===='
docker logs valuehub-mongo --tail 40 || true
echo '==== mysql ===='
docker inspect -f '{{.State.Health.Status}}' valuehub-mysql || true
docker inspect -f '{{.State.Health.Status}}' valuehub-mongo || true
