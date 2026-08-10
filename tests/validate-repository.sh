#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$REPO_ROOT"

for script in install.sh prepare-mountpoints.sh bin/*; do
    [ -f "$script" ] || continue
    first_line=$(head -1 "$script")
    case "$first_line" in
        '#!'*python*)
            python3 -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(), sys.argv[1], "exec")' "$script"
            ;;
        '#!'*bash*|'#!'*'/sh')
            bash -n "$script"
            ;;
    esac
done

for settings in config/*.json; do
    python3 -m json.tool "$settings" >/dev/null
    python3 - "$settings" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

assert data.get("autoMemoryEnabled") is False
assert data.get("env", {}).get("CLAUDE_CODE_DISABLE_AUTO_MEMORY") == "1"
PY
done

for launcher in bin/claude2 bin/dep-claude1 bin/dep-claude2 bin/pranay-claude bin/pranay-claude2; do
    grep -q -- 'CLAUDE_CODE_DISABLE_AUTO_MEMORY=1' "$launcher"
done

for launcher in bin/dep-codex bin/pranay-codex; do
    grep -q -- 'memories.generate_memories=false' "$launcher"
    grep -q -- 'memories.use_memories=false' "$launcher"
done

grep -q -- 'ensure-codex-memory-off' bin/init-server-codex
grep -q -- 'ensure-codex-memory-off' install.sh

namespace_launchers=(
    bin/dep-claude1 bin/dep-claude2
    bin/pranay-claude bin/pranay-claude2
    bin/dep-codex bin/pranay-codex
)
for launcher in "${namespace_launchers[@]}"; do
    grep -q -- '--propagation slave' "$launcher"
    grep -q -- 'mount --make-rslave /' "$launcher"
    if grep -q -- 'mount --make-rprivate /' "$launcher"; then
        echo "Reconnect-unsafe private propagation found in $launcher" >&2
        exit 1
    fi
    grep -q -- 'GPU_MIRROR_REMOTE_CWD' "$launcher"
done

for router in bin/gpu-shell-dep bin/gpu-shell-pranay bin/gpu-shell-codex-dep bin/gpu-shell-codex-pranay; do
    grep -q -- 'GPU_MIRROR_REMOTE_CWD' "$router"
done

if grep -q -- 'systemctl --user restart' bin/check-claude-mounts; then
    echo "Health checker must not replace an active reconnecting SSHFS mount" >&2
    exit 1
fi

for unit in systemd/claude-mount-*-home.service systemd/claude-mount-*-data.service; do
    grep -q -- 'ExecStop=-/bin/fusermount3 -uz ' "$unit"
done

if grep -R -n --exclude-dir=.git --exclude=README.md \
    --exclude=validate-repository.sh '/home/sayooj' .; then
    echo "Hardcoded workstation home found outside documentation." >&2
    exit 1
fi

if find . -path ./.git -prune -o \
    \( -name auth.json -o -name '*.pem' -o -name '*.key' -o -name '*.sqlite' \) \
    -type f -print | grep -q .; then
    echo "Credential or runtime-state file found in repository." >&2
    exit 1
fi

git diff --check
echo "Repository validation passed."
