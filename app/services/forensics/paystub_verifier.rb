# frozen_string_literal: true

module Forensics
  class PaystubVerifier
    attr_reader :family, :period, :user

    def initialize(family, period: nil, user: nil)
      @family = family
      @period = period
      @user = user
    end

    def build
      date_range = if period.respond_to?(:date_range)
        period.date_range
      elsif period.respond_to?(:start_date) && period.respond_to?(:end_date)
        period.start_date..period.end_date
      elsif period.is_a?(Range)
        period
      else
        30.days.ago.to_date..Date.current
      end

      payroll_categories = family.categories.where("name ILIKE ? OR name ILIKE ?", "%income%", "%payroll%").pluck(:id)

      tx_scope = family.transactions
        .joins(:entry)
        .where(entries: { date: date_range, excluded: false })
        .where("entries.amount < 0")

      if payroll_categories.present?
        tx_scope = tx_scope.where("transactions.category_id IN (?) OR entries.name ILIKE ?", payroll_categories, "%payroll%")
      else
        tx_scope = tx_scope.where("entries.name ILIKE ?", "%payroll%")
      end

      tx_scope = tx_scope.includes(:category, :merchant, entry: :account).order("entries.date DESC")

      payrolls = tx_scope.map do |tx|
        entry = tx.entry
        account = entry&.account
        amt = entry&.amount ? entry.amount.abs.to_f.round(2) : 0.0
        employer = tx.merchant&.name.presence || tx.category&.name.presence || entry&.name.presence || "Employer Deposit"
        account_type = account&.subtype.presence || account&.accountable_type.presence || "Depository"

        {
          id: tx.id,
          date: entry&.date,
          employer: employer,
          account_name: account&.name.presence || "Unknown Account",
          account_type: account_type,
          amount: amt,
          status: account&.status == "active" || account.present? ? "verified" : "unverified"
        }
      end

      total_inflow = payrolls.sum { |p| p[:amount] }.round(2)
      payroll_count = payrolls.size
      avg_paycheck = payroll_count.positive? ? (total_inflow / payroll_count).round(2) : 0.0
      accounts_count = payrolls.map { |p| p[:account_name] }.uniq.size

      currency_symbol = begin
        Money::Currency.new(family.currency).symbol
      rescue StandardError
        "$"
      end

      {
        total_inflow: total_inflow,
        payroll_count: payroll_count,
        avg_paycheck: avg_paycheck,
        accounts_count: accounts_count,
        payrolls: payrolls,
        currency_symbol: currency_symbol
      }
    end
  end
end
