# config/routes/forensics.rb
# frozen_string_literal: true

namespace :forensics do
  get "money_flow", to: "reports#money_flow"
  get "pivot_analysis", to: "reports#pivot_analysis"
  get "temporal_heatmap", to: "reports#temporal_heatmap"
  get "paystub_audit", to: "reports#paystub_audit"
end
