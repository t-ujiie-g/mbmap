#!/usr/bin/env bash
# Prepares a fresh Linux x86_64 machine (Claude Code on the web, a CI runner, a new
# container) for the work in AGENTS.md: the pinned MoonBit toolchain, npm dependencies,
# Chromium for Playwright and, unless --no-fixtures, the GSI fixtures. Safe to run again.
# scripts/setup.sh [--no-fixtures] [--no-browser]
set -euo pipefail
cd "$(dirname "$0")/.."
fixtures=1 browser=1
for a in "$@"; do
  case "$a" in
    --no-fixtures) fixtures=0 ;;
    --no-browser) browser=0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
# shellcheck source=toolchain.env
source scripts/toolchain.env

moon_home="$HOME/.moon"
want="${MOONBIT_VERSION/\%2B/+}"
if ! "$moon_home/bin/moonc" -v 2>/dev/null | grep -qF "${want%%+*}"; then
  tmp=$(mktemp -d)
  base=https://cli.moonbitlang.com
  curl -fsSL -o "$tmp/moonbit.tar.gz" "$base/binaries/$MOONBIT_VERSION/moonbit-linux-x86_64.tar.gz"
  curl -fsSL -o "$tmp/core.tar.gz" "$base/cores/core-$MOONBIT_VERSION.tar.gz"
  echo "$MOONBIT_SHA256  $tmp/moonbit.tar.gz" | sha256sum -c -
  echo "$MOONBIT_CORE_SHA256  $tmp/core.tar.gz" | sha256sum -c -
  rm -rf "$moon_home/bin" "$moon_home/lib/core"
  mkdir -p "$moon_home/lib"
  tar xf "$tmp/moonbit.tar.gz" -C "$moon_home"
  find "$moon_home/bin" -type f -exec chmod +x {} +
  tar xf "$tmp/core.tar.gz" -C "$moon_home/lib"
  PATH="$moon_home/bin:$PATH" moon -C "$moon_home/lib/core" bundle --warn-list -a --all
  PATH="$moon_home/bin:$PATH" moon -C "$moon_home/lib/core" bundle --warn-list -a --target wasm-gc --quiet
  rm -rf "$tmp"
fi
export PATH="$moon_home/bin:$PATH"
# Later shells find moon: through /usr/local/bin when it is writable (a root setup script),
# else through a Claude Code session's env file.
if [ -w /usr/local/bin ]; then
  for f in "$moon_home"/bin/*; do ln -sf "$f" /usr/local/bin/; done
elif [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$moon_home/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
moon version --all

for dir in npm bench examples/react; do
  if [ ! -d "$dir/node_modules" ] || [ "$dir/package-lock.json" -nt "$dir/node_modules" ]; then
    npm ci --prefix "$dir" --no-audit --no-fund
  fi
done
if [ "$browser" = 1 ]; then
  (cd bench && npx playwright install --with-deps chromium)
fi
if [ "$fixtures" = 1 ]; then
  NODE_USE_ENV_PROXY=1 npm --prefix bench run fixtures || echo "setup: fixtures not fetched (is cyberjapandata.gsi.go.jp reachable?); goldens and pack tests need them" >&2
fi
echo "setup: done"
