#!/usr/bin/env bash
set -euo pipefail
mkdir -p api db/migrations frontend
cat > api/app.py <<'EOF'
from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/items")
def items():
    return jsonify(items=[])
EOF
cat > db/migrations/001_create_items.sql <<'EOF'
CREATE TABLE items (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);
EOF
cat > frontend/index.html <<'EOF'
<!doctype html>
<html>
  <body>
    <h1>Items</h1>
    <ul id="items"></ul>
    <script src="app.js"></script>
  </body>
</html>
EOF
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
