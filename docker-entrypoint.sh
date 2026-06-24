#!/usr/bin/env bash
set -euo pipefail

# Start the embedded MongoDB (ephemeral storage under /data/db)
mkdir -p /data/db
echo "[entrypoint] starting mongod..."
mongod --dbpath /data/db --bind_ip 127.0.0.1 --port 27017 \
       --fork --logpath /tmp/mongod.log --quiet

# Wait until Mongo accepts connections
for i in $(seq 1 30); do
  if mongod --version >/dev/null 2>&1 && \
     (exec 3<>/dev/tcp/127.0.0.1/27017) 2>/dev/null; then
    echo "[entrypoint] mongod is up"
    break
  fi
  echo "[entrypoint] waiting for mongod ($i)..."
  sleep 1
done

# Meteor runtime config
export PORT="${PORT:-10000}"
export MONGO_URL="${MONGO_URL:-mongodb://127.0.0.1:27017/meteor}"
export ROOT_URL="${ROOT_URL:-http://localhost:${PORT}}"

echo "[entrypoint] launching Meteor on PORT=${PORT} ROOT_URL=${ROOT_URL}"
exec node /app/main.js
