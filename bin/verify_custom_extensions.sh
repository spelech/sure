#!/usr/bin/env bash
set -e
echo "==> Verifying Sure Custom Extensions..."
if ! grep -q "draw(:forensics)" config/routes.rb; then
  echo "FAIL: draw(:forensics) missing from config/routes.rb"
  exit 1
fi
if [ ! -f config/initializers/forensics.rb ]; then
  echo "FAIL: config/initializers/forensics.rb missing"
  exit 1
fi
echo "SUCCESS: All extension hooks verified."
