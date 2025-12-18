#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/config/bootstrap_manifest.json"

if [ ! -f "$MANIFEST" ]; then
    echo "Manifest not found: $MANIFEST" >&2
    exit 1
fi

echo "Project root: $ROOT_DIR"
echo "Using manifest: $MANIFEST"
echo

jq -r '.files[] | "\(.path)|\(.template)|\(.regen)"' "$MANIFEST" | while IFS='|' read -r relPath tmplPath regen; do
    target="$ROOT_DIR/$relPath"
    tmpl="$ROOT_DIR/$tmplPath"

    #* skip things that are not safe to regenerate
    if [ "$regen" != "true" ]; then
        echo "Skipping (regen=false): $relPath"
        continue
    fi

    if [ -f "$target" ]; then
        echo "Exists, leaving as-is: $relPath"
        continue
    fi

    if [ ! -f "$tmpl" ]; then
        echo "Template missing for $relPath ($tmplPath), skipping" >&2
        continue
    fi

    mkdir -p "$(dirname "$target")"
    cp "$tmpl" "$target"
    echo "Created from template: $relPath"
done

echo
echo "Note: android/key.jks must be generated manually once, e.g.:"
echo "  keytool -genkeypair -v -keystore android/key.jks -alias ditrix_key \\"
echo "    -keyalg RSA -keysize 2048 -validity 10000"
echo
echo "Bootstrap done."