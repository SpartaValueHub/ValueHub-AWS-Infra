#!/usr/bin/env bash
# Run once on DB EC2 (Ubuntu 22.04) as a sudo-capable user.
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl git

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "Docker installed. Log out/in (or newgrp docker) then re-run compose."
fi

sudo mkdir -p /opt/valuehub-aws-infra
sudo chown "$USER:$USER" /opt/valuehub-aws-infra

if [ ! -d /opt/valuehub-aws-infra/.git ]; then
  git clone https://github.com/SpartaValueHub/ValueHub-AWS-Infra.git /opt/valuehub-aws-infra
fi

cd /opt/valuehub-aws-infra
git fetch origin
git checkout main
git pull origin main

if [ ! -f .env ]; then
  cp env/db.env.example .env
  echo "Created .env — set MYSQL_ROOT_PASSWORD, MONGODB_PASSWORD, MONGODB_ADVERTISE_HOST=<this-private-ip>"
fi

echo "Next:"
echo "  1) Edit /opt/valuehub-aws-infra/.env (MONGODB_ADVERTISE_HOST = this EC2 private IP)"
echo "  2) docker compose -f compose.prod-db.yml --env-file .env up -d"
echo "  3) Open SG: MySQL 3306 / Mongo 27017 from Apps SG only"
