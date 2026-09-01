# frozen_string_literal: true

module Forensics
  class TemporalHeatmapBuilder
    attr_reader :family, :period, :user

    def initialize(family, period: nil, user: nil)
      @family = family
      @period = period
      @user = user
    end

    def build
      start_date = 365.days.ago.to_date
      end_date = Date.current

      tx_scope = family.transactions
        .joins(:entry)
        .where(entries: { date: start_date..end_date, excluded: false })
        .where("entries.amount > 0") # Outflows in Sure
        .where.not(kind: Transaction::BUDGET_EXCLUDED_KINDS)
        .includes(:merchant, :entry)

      daily_spend = Hash.new { |h, k| h[k] = { total: 0.0, count: 0 } }
      merchant_aggregates = Hash.new do |h, k|
        h[k] = {
          id: k,
          name: k,
          total: 0.0,
          count: 0,
          daily_totals: Hash.new(0.0)
        }
      end

      tx_records = tx_scope.to_a
      tx_records.each do |tx|
        amt = tx.entry&.amount ? tx.entry.amount.to_f.abs : 0.0
        next if amt <= 0.0

        date_str = tx.entry.date.iso8601
        daily_spend[date_str][:total] += amt
        daily_spend[date_str][:count] += 1

        merch_name = tx.merchant&.name.presence || "Other Merchants"
        m = merchant_aggregates[merch_name]
        m[:total] += amt
        m[:count] += 1
        m[:daily_totals][date_str] += amt
      end

      days = []
      date_cursor = start_date
      total_year_spend = 0.0

      while date_cursor <= end_date
        date_str = date_cursor.iso8601
        stats = daily_spend[date_str]
        day_total = (stats ? stats[:total] : 0.0).round(2)
        day_count = stats ? stats[:count] : 0

        total_year_spend += day_total

        days << {
          date: date_str,
          day_of_week: date_cursor.wday,
          month: date_cursor.month,
          year: date_cursor.year,
          total: day_total,
          count: day_count
        }

        date_cursor += 1.day
      end

      top_merchants = merchant_aggregates.values
        .sort_by { |m| -m[:total] }
        .first(20)
        .map do |m|
          {
            id: m[:id],
            name: m[:name],
            total: m[:total].round(2),
            count: m[:count],
            daily_totals: m[:daily_totals].transform_values { |v| v.round(2) }
          }
        end

      currency_symbol = begin
        Money::Currency.new(family.currency).symbol
      rescue StandardError
        "$"
      end

      {
        days: days,
        top_merchants: top_merchants,
        total_year_spend: total_year_spend.round(2),
        currency_symbol: currency_symbol
      }
    end
  end
end
