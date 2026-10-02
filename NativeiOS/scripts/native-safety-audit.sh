#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "HALO native crash-safety audit"
PATTERN='fatalError\(|preconditionFailure\(|try!([[:space:]]|$)|[[:space:]]as![[:space:]]'
MATCHES="$(grep -RInE "$PATTERN" HaloField --include='*.swift' || true)"

if [ -n "$MATCHES" ]; then
  echo "ERROR: Crash-prone Swift construct found in production HALO source:"
  echo "$MATCHES"
  echo "Use recoverable error handling, optional casts, or guarded state instead."
  exit 1
fi

echo "PASS: no fatalError, preconditionFailure, try!, or forced as! casts in HaloField Swift sources."
