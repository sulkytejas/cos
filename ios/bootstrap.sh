#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "→ Installing xcodegen via Homebrew (one-time)..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "✗ Homebrew not found. Install from https://brew.sh and re-run."
    exit 1
  fi
  brew install xcodegen
fi

echo "→ Generating Atlas.xcodeproj from project.yml..."
xcodegen generate --quiet

echo ""
echo "✓ Done. Next steps:"
echo "  1. open Atlas.xcodeproj"
echo "  2. In Xcode: select your iPhone (or a simulator) at the top"
echo "  3. Signing & Capabilities → choose your Team (Personal or paid)"
echo "  4. Cmd+R"
echo ""
