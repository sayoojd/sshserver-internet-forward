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
