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

CAMERA_SOURCE="HaloField/Features/Camera/HaloCamera.swift"
if grep -Eq 'defer[[:space:]]*\{[^}]*commitConfiguration\(\)' "$CAMERA_SOURCE"; then
  echo "ERROR: Camera configuration uses deferred commitConfiguration()."
  echo "AVCaptureSession must commit configuration before startRunning() is called."
  exit 1
fi

BEGIN_CONFIGURATION_LINE="$(grep -nF 'self.session.beginConfiguration()' "$CAMERA_SOURCE" | head -n 1 | cut -d: -f1)"
COMMIT_CONFIGURATION_LINE="$(grep -nF 'self.session.commitConfiguration()' "$CAMERA_SOURCE" | tail -n 1 | cut -d: -f1)"
START_RUNNING_LINE="$(grep -nF 'self.session.startRunning()' "$CAMERA_SOURCE" | tail -n 1 | cut -d: -f1)"

if [ -z "$BEGIN_CONFIGURATION_LINE" ] || [ -z "$COMMIT_CONFIGURATION_LINE" ] || \
   [ -z "$START_RUNNING_LINE" ] || \
   [ "$BEGIN_CONFIGURATION_LINE" -ge "$COMMIT_CONFIGURATION_LINE" ] || \
   [ "$COMMIT_CONFIGURATION_LINE" -ge "$START_RUNNING_LINE" ]; then
  echo "ERROR: Camera session must call commitConfiguration() before startRunning()."
  exit 1
fi

echo "PASS: no fatalError, preconditionFailure, try!, or forced as! casts in HaloField Swift sources."
echo "PASS: camera session commits configuration before starting capture."
