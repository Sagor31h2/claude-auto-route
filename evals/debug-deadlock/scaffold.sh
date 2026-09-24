#!/usr/bin/env bash
set -euo pipefail
cat > worker_pool.py <<'EOF'
import threading

queue_lock = threading.Lock()
stats_lock = threading.Lock()
jobs = []
processed = 0


def submit(job):
    with queue_lock:
        jobs.append(job)
        with stats_lock:
            pass


def worker():
    global processed
    while True:
        with stats_lock:
            processed += 1
            with queue_lock:
                if not jobs:
                    return
                jobs.pop()


def run(n_workers=8):
    threads = [threading.Thread(target=worker) for _ in range(n_workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
EOF
{ git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.com commit -qm init; } || true
