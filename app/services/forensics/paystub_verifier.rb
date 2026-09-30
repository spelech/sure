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
        .where(entries: { date: date_range, parent_entry_id: nil })
        .where("entries.amount < 0") # Inflows (negative in Sure)
        .where("entries.excluded = false OR entries.id IN (SELECT DISTINCT parent_entry_id FROM entries WHERE parent_entry_id IS NOT NULL)")

      if payroll_categories.present?
        tx_scope = tx_scope.where("transactions.category_id IN (?) OR entries.name ILIKE ?", payroll_categories, "%payroll%")
      else
        tx_scope = tx_scope.where("entries.name ILIKE ?", "%payroll%")
      end

      tx_scope = tx_scope.includes(:category, :merchant, entry: [:account, :child_entries]).order("entries.date DESC")

      total_gross = 0.0
      total_taxes = 0.0
      total_pretax = 0.0
      total_posttax = 0.0
      reconciled_count = 0
      unreconciled_count = 0

      payrolls = tx_scope.map do |tx|
        entry = tx.entry
        account = entry&.account
        net_amt = entry&.amount ? entry.amount.abs.to_f.round(2) : 0.0
        employer = tx.merchant&.name.presence || tx.category&.name.presence || entry&.name.presence || "Employer Deposit"
        account_type = account&.subtype.presence || account&.accountable_type.presence || "Depository"

        # Check ActiveStorage attachments on Transaction or Entry
        attachment_names = []
        if tx.attachments.attached?
          attachment_names.concat(tx.attachments.map { |a| a.filename.to_s })
        end
        if entry&.receipts&.attached?
          attachment_names.concat(entry.receipts.map { |r| r.filename.to_s })
        end
        has_attachment = attachment_names.any?

        # Check split line items
        is_split = entry&.split_parent? || false
        gross_val = 0.0
        tax_val = 0.0
        pretax_val = 0.0
        posttax_val = 0.0

        if is_split && entry.child_entries.any?
          entry.child_entries.each do |child|
            child_name = child.name.to_s.downcase
            child_amt = child.amount.abs.to_f.round(2)
            if child_name.include?("gross")
              gross_val += child_amt
            elsif child_name.include?("pre-tax") || child_name.include?("pretax") || child_name.include?("benefit") || child_name.include?("401k")
              pretax_val += child_amt
            elsif child_name.include?("post-tax") || child_name.include?("posttax") || child_name.include?("roth")
              posttax_val += child_amt
            elsif child_name.include?("tax") || child_name.include?("withholding")
              tax_val += child_amt
            end
          end
        end

        total_gross += gross_val
        total_taxes += tax_val
        total_pretax += pretax_val
        total_posttax += posttax_val

        # Deterministic verification classification
        status = if is_split && has_attachment
          reconciled_count += 1
          "reconciled"
        elsif is_split && !has_attachment
          unreconciled_count += 1
          "split_only"
        elsif !is_split && has_attachment
          unreconciled_count += 1
          "pdf_only"
        else
          unreconciled_count += 1
          "unattached_deposit"
        end

        {
          id: tx.id,
          date: entry&.date,
          employer: employer,
          account_name: account&.name.presence || "Unknown Account",
          account_type: account_type,
          amount: net_amt,
          gross_pay: gross_val > 0 ? gross_val : nil,
          taxes: tax_val > 0 ? tax_val : nil,
          pre_tax: pretax_val > 0 ? pretax_val : nil,
          post_tax: posttax_val > 0 ? posttax_val : nil,
          has_attachment: has_attachment,
          attachment_names: attachment_names,
          is_split: is_split,
          status: status
        }
      end

      total_net_inflow = payrolls.sum { |p| p[:amount] }.round(2)
      payroll_count = payrolls.size
      avg_paycheck = payroll_count.positive? ? (total_net_inflow / payroll_count).round(2) : 0.0
      accounts_count = payrolls.map { |p| p[:account_name] }.uniq.size

      currency_symbol = begin
        Money::Currency.new(family.currency).symbol
      rescue StandardError
        "$"
      end

      {
        total_inflow: total_net_inflow,
        total_gross: total_gross.round(2),
        total_taxes: total_taxes.round(2),
        total_deductions: (total_pretax + total_posttax).round(2),
        payroll_count: payroll_count,
        reconciled_count: reconciled_count,
        unreconciled_count: unreconciled_count,
        avg_paycheck: avg_paycheck,
        accounts_count: accounts_count,
        payrolls: payrolls,
        currency_symbol: currency_symbol
      }
    end
  end
end
