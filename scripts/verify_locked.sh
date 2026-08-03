#!/usr/bin/env bash
# Run a ShopPilotVerify* (or any) product under the global Swift lock.
#
# Usage:
#   ./scripts/verify_locked.sh ShopPilotVerify1103a
#   ./scripts/verify_locked.sh ShopPilotVerify1100 -- --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <product> [extra swift run args...]" >&2
  echo "example: $0 ShopPilotVerify1103a" >&2
  exit 2
fi

PRODUCT="$1"
shift

exec "${SCRIPT_DIR}/swift_locked.sh" run "${PRODUCT}" "$@"
