#!/usr/bin/env bash
# Bump a vendored Lerd pin and refresh the fixed-output derivation hashes
# (srcHash, npmDepsHash, vendorHash) that go stale when the version moves.
# See UPDATE_PACKAGE.md for what this does and how to do it by hand.
#
#   ./update-package.sh <version>
#   ./update-package.sh <version> beta.nix [lerd-beta]
#
# package.nix holds the stable defaults (flake attr `default`).
# beta.nix holds the beta channel (flake attr `lerd-beta`).
set -euo pipefail

usage() {
  echo "Usage: $0 <new-version> [package.nix|beta.nix] [flake-attr]" >&2
  echo "Example: $0 1.27.1" >&2
  echo "         $0 1.38.0-beta.1 beta.nix" >&2
  exit 1
}

[ $# -ge 1 ] && [ $# -le 3 ] || usage
NEW_VERSION="$1"
PINS_NAME="${2:-package.nix}"
case "$PINS_NAME" in
  package.nix) ATTR="${3:-default}" ;;
  beta.nix) ATTR="${3:-lerd-beta}" ;;
  *) usage ;;
esac

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "Version must look like 1.27.1 or 1.38.0-beta.1 (no leading v): ${NEW_VERSION}" >&2
  exit 1
fi
if ! [[ "$ATTR" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Refusing flake attr: ${ATTR}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="$SCRIPT_DIR/$PINS_NAME"
if [ ! -f "$PKG_FILE" ]; then
  echo "Pins file not found: $PKG_FILE" >&2
  exit 1
fi

# Rewrite key = "..." or key ? "..." (the stable defaults use `?`).
# `|` is the delimiter because a base64 hash can contain `/`.
replace_quoted() {
  local key="$1" value="$2"
  if ! grep -qE "${key}[[:space:]]*[=?]" "$PKG_FILE"; then
    echo "Could not find ${key} in ${PKG_FILE}" >&2
    exit 1
  fi
  sed -i.bak -E "s|(${key}[[:space:]]*[=?][[:space:]]*)\"[^\"]*\"|\\1\"${value}\"|" "$PKG_FILE"
  rm -f "$PKG_FILE.bak"
}

CURRENT_VERSION=$(sed -n -E 's/.*version[[:space:]]*[=?][[:space:]]*"([^"]+)".*/\1/p' "$PKG_FILE" | head -1)
echo "Updating ${PINS_NAME}: ${CURRENT_VERSION:-unknown} -> ${NEW_VERSION} (.#${ATTR})"
replace_quoted version "$NEW_VERSION"

apply_hash() {
  local field="$1" value="$2"
  case "$field" in
    src) replace_quoted srcHash "$value" ;;
    npmDeps) replace_quoted npmDepsHash "$value" ;;
    vendor) replace_quoted vendorHash "$value" ;;
    *)
      echo "Unknown hash field: ${field}" >&2
      exit 1
      ;;
  esac
}

BUILT=0
MAX_ITER=5
for i in $(seq 1 "$MAX_ITER"); do
  echo "== Build attempt ${i}/${MAX_ITER} =="
  if output=$(nix build "${SCRIPT_DIR}#${ATTR}" --no-link 2>&1); then
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

RESULT_PATH=$(nix build "${SCRIPT_DIR}#${ATTR}" --no-link --print-out-paths)
echo
echo "Built: ${RESULT_PATH}"
"${RESULT_PATH}/bin/lerd" --version || true

echo
echo "${PINS_NAME} now points at ${NEW_VERSION}. Review the diff before committing:"
echo "  git -C \"${SCRIPT_DIR}\" diff ${PINS_NAME}"
