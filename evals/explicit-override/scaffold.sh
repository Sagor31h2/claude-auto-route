#!/usr/bin/env bash
set -euo pipefail
cat > README.md <<'EOF'
# Event service

The service will recieve events from the queue and store them in the database.
EOF
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
