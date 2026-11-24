#!/usr/bin/env bash
set -euo pipefail
mkdir -p pkg tests
for i in 01 02 03 04 05 06 07 08 09 10; do
  cat > pkg/mod$i.py <<PY
def process(x):
    """process(x) returns x plus $i."""
    return x + $i
PY
  cat > tests/test_mod$i.py <<PY
from pkg.mod$i import process


def test_process():
    assert process(1) == $((10#$i + 1))
PY
done
touch pkg/__init__.py
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
