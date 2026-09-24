#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat > src/http_client.py <<'EOF'
import time
import urllib.request


def get_with_retry(url, retries=3, backoff=0.5):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                return resp.read()
        except OSError:
            if attempt == retries - 1:
                raise
            time.sleep(backoff * (2 ** attempt))
EOF
cat > src/app.py <<'EOF'
from http_client import get_with_retry


def fetch_status():
    return get_with_retry("https://example.com/status")
EOF
cat > src/utils.py <<'EOF'
def slugify(text):
    return "-".join(text.lower().split())
EOF
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
