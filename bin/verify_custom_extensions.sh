#!/usr/bin/env bash
set -e

echo "========================================================"
echo "  Sure Custom Extensions Upgrade & Integrity Verifier  "
echo "========================================================"

FAILED=0

check_file() {
  if [ -f "$1" ]; then
    echo "  [PASS] $1 exists"
  else
    echo "  [FAIL] $1 missing"
    FAILED=1
  fi
}

echo "--> Checking Route Hook..."
if grep -q "draw(:forensics)" config/routes.rb; then
  echo "  [PASS] config/routes.rb contains draw(:forensics)"
else
  echo "  [FAIL] config/routes.rb missing draw(:forensics)"
  FAILED=1
fi

echo "--> Checking Extension Files..."
check_file "config/routes/forensics.rb"
check_file "config/initializers/forensics.rb"
check_file "app/extensions/forensics/services/money_flow_builder.rb"
check_file "app/extensions/forensics/services/pivot_table_builder.rb"
check_file "app/extensions/forensics/services/temporal_heatmap_builder.rb"
check_file "app/extensions/forensics/services/paystub_verifier.rb"
check_file "app/extensions/forensics/controllers/forensic_reports_controller.rb"
check_file "app/views/reports/forensics/_money_flow.html.erb"
check_file "app/views/reports/forensics/_pivot_analysis.html.erb"
check_file "app/views/reports/forensics/_temporal_heatmap.html.erb"
check_file "app/views/reports/forensics/_paystub_audit.html.erb"
check_file "app/javascript/controllers/forensics/pivot_table_controller.js"
check_file "app/javascript/controllers/forensics/heatmap_controller.js"

echo "--> Checking Ruby Syntax across Extensions..."
for f in $(find app/extensions/forensics test/extensions/forensics config/routes/forensics.rb config/initializers/forensics.rb -name "*.rb"); do
  if docker run --rm -v "$(pwd):/rails" -w /rails ghcr.io/we-promise/sure:stable ruby -c "$f" >/dev/null 2>&1; then
    echo "  [PASS] Syntax OK: $f"
  else
    echo "  [FAIL] Syntax Error: $f"
    FAILED=1
  fi
done

if [ $FAILED -eq 0 ]; then
  echo "========================================================"
  echo "  ALL CHECKS PASSED: Custom Extensions 100% Intact!    "
  echo "========================================================"
  exit 0
else
  echo "========================================================"
  echo "  VERIFICATION FAILED: Please review errors above.      "
  echo "========================================================"
  exit 1
fi
