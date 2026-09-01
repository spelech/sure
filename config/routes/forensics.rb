# config/routes/forensics.rb
# frozen_string_literal: true

scope :forensics do
  get "money_flow", to: "forensic_reports#money_flow"
  get "pivot_analysis", to: "forensic_reports#pivot_analysis"
  get "temporal_heatmap", to: "forensic_reports#temporal_heatmap"
  get "paystub_audit", to: "forensic_reports#paystub_audit"
end
