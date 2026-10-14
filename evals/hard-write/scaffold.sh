#!/usr/bin/env bash
set -euo pipefail
cat > bank.py <<'PY'
accounts = {"a": 100, "b": 100}


def transfer(src, dst, amount):
    if accounts[src] < amount:
        raise ValueError("insufficient funds")
    accounts[src] -= amount
    accounts[dst] += amount
PY
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
