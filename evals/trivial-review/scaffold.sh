#!/usr/bin/env bash
set -euo pipefail
cat > greet.py <<'PY'
def greet(name):
    return "Hello, " + name
PY
cat > test_greet.py <<'PY'
from greet import greet


def test_greet():
    assert greet("Ann") == "Hello, Ann"
    assert greet() == "Hello, world"
PY
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
cat > greet.py <<'PY'
def greet(name="world"):
    """Return a greeting."""
    return "Hello, " + name
PY
