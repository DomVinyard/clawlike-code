#!/usr/bin/env bash
# session-start.sh — clawlike-code SessionStart hook.
# Delegates to lib/inject.sh to build the <persistent-memory> envelope.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$PLUGIN_DIR/lib/inject.sh"
