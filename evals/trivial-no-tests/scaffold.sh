#!/usr/bin/env bash
set -euo pipefail
cat > pages.py <<'PY'
def page_count(total, per_page):
    return total // per_page + 1
PY
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
