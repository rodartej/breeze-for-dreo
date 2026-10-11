#!/bin/zsh
# Lists localizable strings in the code that a language file is missing.
#   scripts/check-strings.sh [lang]   (default: every Resources/*.lproj except en)
set -euo pipefail
cd "${0:A:h}/.."
out=.build/strings
rm -rf "$out" && mkdir -p "$out"
swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos15.0" -wmo -c -module-name Breeze \
  -emit-localized-strings -emit-localized-strings-path "$out" Sources/*.swift -o "$out/all.o"
langs=(${1:-${(@)${(f)"$(ls -d Resources/*.lproj | xargs -n1 basename | sed 's/.lproj//' | grep -vx en)"}}})
python3 - "$out" $langs <<'PY'
import glob, json, subprocess, sys
out, langs = sys.argv[1], sys.argv[2:]
keys = {e["key"] for f in glob.glob(f"{out}/*.stringsdata")
        for entries in json.load(open(f)).get("tables", {}).values() for e in entries}
failed = False
for lang in langs:
    path = f"Resources/{lang}.lproj/Localizable.strings"
    have = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", path]))
    missing, unused = sorted(keys - have.keys()), sorted(have.keys() - keys)
    print(f"{lang}: {len(keys) - len(missing)}/{len(keys)} translated")
    for k in missing: print(f"  missing: {k!r}")
    for k in unused: print(f"  unused:  {k!r}")
    failed |= bool(missing)
sys.exit(1 if failed else 0)
PY
