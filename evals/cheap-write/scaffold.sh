#!/usr/bin/env bash
set -euo pipefail
cat > slugify.py <<'PY'
def slugify(text):
    raise NotImplementedError
PY
cat > test_slugify.py <<'PY'
from slugify import slugify


def test_basic():
    assert slugify("Hello, World!") == "hello-world"


def test_runs_and_edges():
    assert slugify("  --A  b__c--  ") == "a-b-c"
PY
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
