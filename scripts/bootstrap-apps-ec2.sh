#!/usr/bin/env bash
# Run once on Apps EC2 (Ubuntu 22.04) as a sudo-capable user.
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

mkdir -p secrets
if [ ! -f .env ]; then
  cp env/apps.env.example .env
  echo "Created .env — edit MYSQL_HOST, passwords, AUTH_ALLOWED_ORIGINS"
fi

echo "Next:"
echo "  1) Edit /opt/valuehub-aws-infra/.env"
echo "  2) Place JWT PEMs under /opt/valuehub-aws-infra/secrets/"
echo "  3) docker compose -f compose.prod-apps.yml --env-file .env up -d"
