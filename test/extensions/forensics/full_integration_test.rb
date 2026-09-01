# test/extensions/forensics/full_integration_test.rb
require "test_helper"

class FullIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
  end

  test "reports controller includes all 4 forensic extension sections" do
    get reports_path
    assert_response :success

    sections = @controller.instance_variable_get(:@reports_sections) || []
    section_keys = sections.map { |s| s[:key] }

    assert_includes section_keys, "forensic_money_flow", "Missing forensic_money_flow section"
    assert_includes section_keys, "forensic_pivot", "Missing forensic_pivot section"
    assert_includes section_keys, "forensic_heatmap", "Missing forensic_heatmap section"
    assert_includes section_keys, "forensic_paystub_audit", "Missing forensic_paystub_audit section"
  end

  test "forensic routes are drawn and recognized" do
    assert_routing "/forensics/money_flow", controller: "forensic_reports", action: "money_flow"
    assert_routing "/forensics/pivot_analysis", controller: "forensic_reports", action: "pivot_analysis"
    assert_routing "/forensics/temporal_heatmap", controller: "forensic_reports", action: "temporal_heatmap"
    assert_routing "/forensics/paystub_audit", controller: "forensic_reports", action: "paystub_audit"
  end
end
