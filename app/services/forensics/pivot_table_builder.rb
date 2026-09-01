# frozen_string_literal: true

module Forensics
  class PivotTableBuilder
    attr_reader :family, :period, :user

    def initialize(family, period: nil, user: nil)
      @family = family
      @period = period
      @user = user
    end

    def build
      date_range = if period.respond_to?(:date_range)
        period.date_range
      elsif period.is_a?(Range)
        period
      else
        30.days.ago.to_date..Date.current
      end

      tx_scope = family.transactions
        .joins(:entry)
        .where(entries: { date: date_range, excluded: false })
        .where("entries.amount > 0") # Outflows
        .where.not(kind: Transaction::BUDGET_EXCLUDED_KINDS)
        .includes(:category, :merchant, entry: :account)

      tx_records = tx_scope.to_a
      total_outflow = tx_records.sum { |t| t.entry&.amount ? t.entry.amount.to_f.abs : 0.0 }.round(2)

      currency_symbol = begin
        Money::Currency.new(family.currency).symbol
      rescue StandardError
        "$"
      end

      {
        total_outflow: total_outflow,
        currency_symbol: currency_symbol,
        categories: aggregate_by(tx_records, total_outflow) { |t| t.category&.name.presence || "Uncategorized" },
        merchants: aggregate_by(tx_records, total_outflow) { |t| t.merchant&.name.presence || "Other Merchants" },
        months: aggregate_by(tx_records, total_outflow) { |t| t.entry&.date ? t.entry.date.strftime("%b %Y") : "Unknown" },
        accounts: aggregate_by(tx_records, total_outflow) { |t| t.entry&.account&.name.presence || "Unknown Account" }
      }
    end

    private

    def aggregate_by(txs, total_sum)
      grouped = Hash.new { |h, k| h[k] = { count: 0, total: 0.0, max: 0.0 } }

      txs.each do |t|
        key = yield(t)
        amt = t.entry&.amount ? t.entry.amount.to_f.abs : 0.0
        next if amt <= 0.0

        grouped[key][:count] += 1
        grouped[key][:total] += amt
        grouped[key][:max] = amt if amt > grouped[key][:max]
      end

      grouped.map do |key, stats|
        avg = stats[:count].positive? ? (stats[:total] / stats[:count]) : 0.0
        pct = total_sum.positive? ? (stats[:total] / total_sum * 100.0) : 0.0

        {
          key: key,
          count: stats[:count],
          total: stats[:total].round(2),
          avg: avg.round(2),
          max: stats[:max].round(2),
          percentage: pct.round(1)
        }
      end.sort_by { |r| -r[:total] }
    end
  end
end
