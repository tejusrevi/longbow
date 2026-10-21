#!/bin/sh
# Nightly Postgres dump (cron on the server, see deploy.sh). Keeps 14 days in
# ~/backups. These live on the same disk as the database: they cover mistakes
# and corruption, not losing the VM.
set -eu
cd "$(dirname "$0")"
mkdir -p "$HOME/backups"
stamp=$(date -u +%Y%m%d-%H%M%S)
docker compose -f docker-compose.prod.yml exec -T postgres pg_dump -U nakama -Fc nakama > "$HOME/backups/nakama-$stamp.dump"
find "$HOME/backups" -name 'nakama-*.dump' -mtime +14 -delete
