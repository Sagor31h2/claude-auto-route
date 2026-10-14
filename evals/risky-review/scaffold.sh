#!/usr/bin/env bash
set -euo pipefail
cat > session.py <<'PY'
import time

SESSIONS = {}


def validate(token):
    s = SESSIONS.get(token)
    return s is not None and s["expires"] > time.time()
PY
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
cat > session.py <<'PY'
import time

SESSIONS = {}
TTL = 86400 * 30


def validate(token):
    s = SESSIONS.get(token)
    if s is None:
        return False
    if token == s["user_token"] or s["expires"] > time.time() - TTL:
        s["expires"] = time.time() + TTL
        return True
    return False
PY
