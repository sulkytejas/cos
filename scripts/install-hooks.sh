#!/usr/bin/env bash
#
# Install Atlas git hooks (SERVER_ARCHITECTURE.md §4.f).
#
# Symlinks scripts/pre-commit → .git/hooks/pre-commit so every commit runs the
# gitleaks secret scan. Run once per clone:
#
#   ./scripts/install-hooks.sh
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
HOOK_SRC="${ROOT}/scripts/pre-commit"
HOOK_DST="${ROOT}/.git/hooks/pre-commit"

chmod +x "${HOOK_SRC}"
ln -sf "${HOOK_SRC}" "${HOOK_DST}"

echo "✓ installed pre-commit hook → ${HOOK_DST}"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "⚠ gitleaks is not on PATH — install it so the hook can run:"
  echo "    brew install gitleaks"
fi
