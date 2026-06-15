#!/bin/sh
# Pre-alphaclaw startup hook. Logs disk usage and prunes known-safe bloat
# before handing control to alphaclaw.

set -u

echo "[startup] === Pre-cleanup disk usage ==="
df -h /data 2>&1 || true

echo "[startup] /data top-level (incl. dotfiles):"
du -sh /data/* /data/.[!.]* 2>/dev/null | sort -h || true

echo "[startup] /data/.openclaw (incl. dotfiles):"
du -sh /data/.openclaw/* /data/.openclaw/.[!.]* 2>/dev/null | sort -h || true

echo "[startup] /data/.openclaw/agents top-level:"
du -sh /data/.openclaw/agents/* 2>/dev/null | sort -h || true

echo "[startup] /data/.openclaw/plugin-runtime-deps subdirs:"
du -sh /data/.openclaw/plugin-runtime-deps/* 2>/dev/null | sort -h || true

# ---- Cleanup ----

# 1) Old plugin-runtime-deps versions — keep newest 1
PRD_DIR=/data/.openclaw/plugin-runtime-deps
if [ -d "$PRD_DIR" ]; then
    echo "[startup] === Cleanup: plugin-runtime-deps (keep newest 1) ==="
    ls -1dt "$PRD_DIR"/openclaw-* 2>/dev/null | tail -n +2 | while IFS= read -r dir; do
        echo "[startup] rm $dir"
        rm -rf "$dir"
    done
fi

# 2) /data/cache — purgeable by name, recreated as needed
if [ -d /data/cache ]; then
    BEFORE=$(du -sh /data/cache 2>/dev/null | cut -f1)
    echo "[startup] === Cleanup: /data/cache (was ${BEFORE:-unknown}) ==="
    rm -rf /data/cache/* /data/cache/.[!.]* 2>/dev/null || true
fi

# 3) Watchdog DB — high-churn event log, recreated by alphaclaw on next write
for f in /data/db/watchdog.db /data/db/watchdog.db-wal /data/db/watchdog.db-shm; do
    if [ -f "$f" ]; then
        BEFORE=$(du -sh "$f" 2>/dev/null | cut -f1)
        echo "[startup] rm $f (was ${BEFORE:-unknown})"
        rm -f "$f"
    fi
done

# 4) Old openclaw.json snapshots — keep .bak (most recent), .bak.1, .last-good
echo "[startup] === Cleanup: old openclaw.json snapshots ==="
for f in /data/.openclaw/openclaw.json.bak.[2-9] \
         /data/.openclaw/openclaw.json.clobbered.* \
         /data/.openclaw/openclaw.json.backup; do
    [ -e "$f" ] || continue
    echo "[startup] rm $f"
    rm -f "$f"
done

# 5) Agent session bak files — keep newest 3 per session UUID, delete the rest.
#    alphaclaw writes <uuid>.jsonl.bak-<seq>-<ms> on every session mutation; they
#    accumulate forever. The live <uuid>.jsonl is the source of truth; bak files
#    are crash-recovery snapshots. 3 is enough headroom for any plausible rollback.
SESS_DIR=/data/.openclaw/agents/main/sessions
if [ -d "$SESS_DIR" ]; then
    echo "[startup] === Cleanup: session bak files (keep newest 3 per UUID) ==="
    BAK_BEFORE=$(ls "$SESS_DIR"/*.jsonl.bak-* 2>/dev/null | wc -l)
    if [ "$BAK_BEFORE" -gt 0 ]; then
        ls "$SESS_DIR"/*.jsonl.bak-* 2>/dev/null \
            | sed -E 's|^(.*)\.jsonl\.bak-.*$|\1|' \
            | sort -u \
            | while IFS= read -r prefix; do
                ls -1t "${prefix}".jsonl.bak-* 2>/dev/null | tail -n +4 | xargs -r rm -f
              done
        BAK_AFTER=$(ls "$SESS_DIR"/*.jsonl.bak-* 2>/dev/null | wc -l)
        echo "[startup] bak files: $BAK_BEFORE → $BAK_AFTER"
    else
        echo "[startup] no bak files found"
    fi
fi

echo "[startup] === Post-cleanup disk usage ==="
df -h /data 2>&1 || true
du -sh /data/.openclaw/* /data/.openclaw/.[!.]* 2>/dev/null | sort -h | tail -20 || true

echo "[startup] === Launching alphaclaw ==="
exec alphaclaw start
