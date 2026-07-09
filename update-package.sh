#!/usr/bin/env bash
# Bump the vendored Lerd version in package.nix and refresh the fixed-output
# derivation hashes (src, npmDepsHash, vendorHash) that go stale when it moves.
# See UPDATE_PACKAGE.md for what this does and how to do it by hand.
set -euo pipefail

usage() {
  echo "Usage: $0 <new-version>" >&2
  echo "Example: $0 1.27.1   (no leading 'v')" >&2
  exit 1
}

[ $# -eq 1 ] || usage
NEW_VERSION="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="$SCRIPT_DIR/package.nix"

CURRENT_VERSION=$(sed -n -E 's/.*version = "([^"]+)".*/\1/p' "$PKG_FILE" | head -1)
echo "Updating lerd: ${CURRENT_VERSION} -> ${NEW_VERSION}"

sed -i.bak -E "s/version = \"[^\"]+\";/version = \"${NEW_VERSION}\";/" "$PKG_FILE"
rm -f "$PKG_FILE.bak"

apply_hash() {
  local field="$1" value="$2"
  case "$field" in
    src)
      # The src hash sits on the line right after `rev = "v${version}";`.
      local rev_line
      rev_line=$(grep -Fn 'rev = "v${version}"' "$PKG_FILE" | head -1 | cut -d: -f1)
      if [ -z "$rev_line" ]; then
        echo "Could not find the src rev line in $PKG_FILE" >&2
        exit 1
      fi
      local hash_line=$((rev_line + 1))
      # Use | as the sed delimiter: a base64 hash can contain /, which would
      # otherwise close the s/// command early (e.g. sha256-...GzPI/A=).
      sed -i.bak -E "${hash_line}s|hash = \"[^\"]*\"|hash = \"${value}\"|" "$PKG_FILE"
      ;;
    npmDeps)
      sed -i.bak -E "s|npmDepsHash = \"[^\"]*\"|npmDepsHash = \"${value}\"|" "$PKG_FILE"
      ;;
    vendor)
      sed -i.bak -E "s|vendorHash = \"[^\"]*\"|vendorHash = \"${value}\"|" "$PKG_FILE"
      ;;
  esac
  rm -f "$PKG_FILE.bak"
}

BUILT=0
MAX_ITER=5
for i in $(seq 1 "$MAX_ITER"); do
  echo "== Build attempt ${i}/${MAX_ITER} =="
  if output=$(nix build "${SCRIPT_DIR}#default" --no-link 2>&1); then
    echo "$output"
    echo "Build succeeded."
    BUILT=1
    break
  fi
  echo "$output"

  mismatches=$(printf '%s\n' "$output" | awk '
    /hash mismatch in fixed-output derivation/ { drv = $0 }
    /got:/ {
      val = $0
      sub(/.*got:[ \t]*/, "", val)
      gsub(/[ \t\r]+$/, "", val)
      field = ""
      if (drv ~ /-source\.drv/) field = "src"
      else if (drv ~ /-go-modules\.drv/) field = "vendor"
      else if (drv ~ /npm-deps\.drv/) field = "npmDeps"
      if (field != "") print field "=" val
    }
  ')

  if [ -z "$mismatches" ]; then
    echo "Build failed for a reason other than a hash mismatch - see output above." >&2
    exit 1
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    field="${line%%=*}"
    value="${line#*=}"
    echo "  -> updating ${field} hash to ${value}"
    apply_hash "$field" "$value"
  done <<< "$mismatches"
done

if [ "$BUILT" != "1" ]; then
  echo "Gave up after ${MAX_ITER} attempts without a successful build." >&2
  exit 1
fi

RESULT_PATH=$(nix build "${SCRIPT_DIR}#default" --no-link --print-out-paths)
echo
echo "Built: ${RESULT_PATH}"
"${RESULT_PATH}/bin/lerd" --version || true

echo
echo "package.nix now points at ${NEW_VERSION}. Review the diff before committing:"
echo "  git -C \"${SCRIPT_DIR}\" diff package.nix"
