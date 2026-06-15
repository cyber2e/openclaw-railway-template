#!/bin/sh
# Pre-alphaclaw startup hook. Logs disk usage and prunes stale plugin-runtime-deps
# version caches before handing control to alphaclaw.

set -u

echo "[startup] === Pre-cleanup disk usage ==="
df -h /data 2>&1 || true
echo "[startup] /data subdirs:"
du -sh /data/* 2>/dev/null | sort -h || true
echo "[startup] /data/.openclaw subdirs:"
du -sh /data/.openclaw/* 2>/dev/null | sort -h || true
echo "[startup] /data/.openclaw/plugin-runtime-deps subdirs:"
du -sh /data/.openclaw/plugin-runtime-deps/* 2>/dev/null | sort -h || true

PRD_DIR=/data/.openclaw/plugin-runtime-deps
if [ -d "$PRD_DIR" ]; then
    echo "[startup] === plugin-runtime-deps cleanup (keep newest 1) ==="
    ls -1dt "$PRD_DIR"/openclaw-* 2>/dev/null | tail -n +2 | while IFS= read -r dir; do
        echo "[startup] Removing $dir"
        rm -rf "$dir"
    done
    KEPT=$(ls -1dt "$PRD_DIR"/openclaw-* 2>/dev/null | head -1)
    echo "[startup] Kept: ${KEPT:-<none>}"
fi

echo "[startup] === Post-cleanup disk usage ==="
df -h /data 2>&1 || true
du -sh /data/.openclaw/* 2>/dev/null | sort -h || true

echo "[startup] === Launching alphaclaw ==="
exec alphaclaw start
