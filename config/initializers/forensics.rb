# config/initializers/forensics.rb
# frozen_string_literal: true

Rails.application.config.to_prepare do
  module ForensicReportsExtension
    def build_reports_sections
      sections = super

      if Current.family&.transactions&.any?
        sections << {
          key: "forensic_money_flow",
          title: "reports.forensics.money_flow.title",
          partial: "reports/forensics/money_flow",
          locals: {
            flow_data: Forensics::MoneyFlowBuilder.new(Current.family, period: @period, user: Current.user).build
          },
          visible: @has_accounts,
          collapsible: true
        }

        sections << {
          key: "forensic_pivot",
          title: "reports.forensics.pivot.title",
          partial: "reports/forensics/pivot_analysis",
          locals: {
            pivot_data: Forensics::PivotTableBuilder.new(Current.family, period: @period, user: Current.user).build
          },
          visible: @has_accounts,
          collapsible: true
        }

        sections << {
          key: "forensic_heatmap",
          title: "reports.forensics.heatmap.title",
          partial: "reports/forensics/temporal_heatmap",
          locals: {
            heatmap_data: Forensics::TemporalHeatmapBuilder.new(Current.family, user: Current.user).build
          },
          visible: @has_accounts,
          collapsible: true
        }

        sections << {
          key: "forensic_paystub_audit",
          title: "reports.forensics.paystub_audit.title",
          partial: "reports/forensics/paystub_audit",
          locals: {
            audit_data: Forensics::PaystubVerifier.new(Current.family, period: @period, user: Current.user).build
          },
          visible: @has_accounts,
          collapsible: true
        }
      end

      sections
    end
  end

  ReportsController.prepend(ForensicReportsExtension)
end
