# frozen_string_literal: true

class ForensicReportsController < ApplicationController
  def money_flow
    render partial: "reports/forensics/money_flow", locals: {
      flow_data: Forensics::MoneyFlowBuilder.new(Current.family, period: current_period, user: Current.user).build
    }
  end

  def pivot_analysis
    render partial: "reports/forensics/pivot_analysis", locals: {
      pivot_data: Forensics::PivotTableBuilder.new(Current.family, period: current_period, user: Current.user).build
    }
  end

  def temporal_heatmap
    render partial: "reports/forensics/temporal_heatmap", locals: {
      heatmap_data: Forensics::TemporalHeatmapBuilder.new(Current.family, user: Current.user).build
    }
  end

  def paystub_audit
    render partial: "reports/forensics/paystub_audit", locals: {
      audit_data: Forensics::PaystubVerifier.new(Current.family, period: current_period, user: Current.user).build
    }
  end

  private

  def current_period
    Period.custom(start_date: 30.days.ago.to_date, end_date: Date.current)
  end
end
