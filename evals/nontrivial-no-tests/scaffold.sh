#!/usr/bin/env bash
set -euo pipefail
cat > config.json <<'J'
{"retries": 3, "log_level": "INFO"}
J
cat > fetcher.py <<'PY'
def fetch(url):
    return "<html>" + url + "</html>"
PY
cat > parser.py <<'PY'
def parse(html):
    return {"body": html.strip()}
PY
cat > store.py <<'PY'
DB = []


def save(record):
    DB.append(record)
PY
cat > main.py <<'PY'
from fetcher import fetch
from parser import parse
from store import save

save(parse(fetch("http://example.com")))
PY
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
