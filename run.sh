#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run.sh — convenience wrapper so you can just type `./run.sh` instead of
# remembering the full flutter run command with flavor flags.
#
# Usage:
#   ./run.sh              → debug on the first available device (dev flavor)
#   ./run.sh -d <id>      → debug on a specific device
#   ./run.sh release      → release build on first device
#   ./run.sh staging      → dev build with staging flavor
#   ./run.sh prod         → release build with prod flavor
#
# Local backend integration: export API_BASE_URL / SOCKET_BASE_URL before
# invoking, e.g.
#   API_BASE_URL=http://localhost:4500/api/v1 SOCKET_BASE_URL=http://localhost:4500 ./run.sh
# ---------------------------------------------------------------------------

set -euo pipefail

FLAVOR="dev"
MODE="debug"
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    release)  MODE="release" ;;
    staging)  FLAVOR="staging" ;;
    prod)     FLAVOR="prod"; MODE="release" ;;
    *)        EXTRA_ARGS+=("$arg") ;;
  esac
done

DEFINES=("--dart-define=FLAVOR=$FLAVOR")

if [[ -n "${API_BASE_URL:-}" ]]; then
  DEFINES+=("--dart-define=API_BASE_URL=$API_BASE_URL")
fi

if [[ -n "${SOCKET_BASE_URL:-}" ]]; then
  DEFINES+=("--dart-define=SOCKET_BASE_URL=$SOCKET_BASE_URL")
fi

echo "▶  flutter run --flavor $FLAVOR ${DEFINES[*]} --$MODE ${EXTRA_ARGS[*]:-}"
flutter run \
  --flavor "$FLAVOR" \
  "${DEFINES[@]}" \
  "--$MODE" \
  "${EXTRA_ARGS[@]:-}"
