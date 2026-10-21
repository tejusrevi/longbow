#!/bin/sh
# Ships the server to the VM and (re)starts it.
#   Server/deploy/deploy.sh            # from the repo root or anywhere
# Needs Server/deploy/.env (git-ignored; see .env.example) and the SSH key
# ~/.ssh/longbow_azure. Build the module first: cd Server && npm run build.
set -eu
HOST=${LONGBOW_HOST:-longbow-duel.canadacentral.cloudapp.azure.com}
KEY=${LONGBOW_SSH_KEY:-$HOME/.ssh/longbow_azure}
here=$(cd "$(dirname "$0")" && pwd)
ssh="ssh -i $KEY -o StrictHostKeyChecking=accept-new longbow@$HOST"

[ -f "$here/.env" ] || { echo "missing $here/.env" >&2; exit 1; }
$ssh 'mkdir -p ~/longbow/modules'
scp -q -i "$KEY" "$here/docker-compose.prod.yml" "$here/Caddyfile" "$here/backup.sh" "$here/.env" "longbow@$HOST:longbow/"
scp -q -i "$KEY" "$here/../modules/index.js" "longbow@$HOST:longbow/modules/"
$ssh 'set -e
cd ~/longbow
chmod 600 .env; chmod +x backup.sh
docker compose -f docker-compose.prod.yml pull -q
docker compose -f docker-compose.prod.yml up -d --remove-orphans
docker compose -f docker-compose.prod.yml restart nakama >/dev/null
{ crontab -l 2>/dev/null | grep -v longbow/backup.sh || true; echo "17 4 * * * $HOME/longbow/backup.sh >> $HOME/backups.log 2>&1"; } | crontab -
docker compose -f docker-compose.prod.yml ps --format "table {{.Service}}\t{{.Status}}"'
