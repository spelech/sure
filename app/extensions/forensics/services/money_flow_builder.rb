# frozen_string_literal: true

module Forensics
  class MoneyFlowBuilder
    attr_reader :family, :period, :user

    def initialize(family, period:, user: nil)
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
        .includes(:category, :merchant, entry: :account)

      # 1. Inflows (negative amount = credit/income in Sure)
      inflows = tx_scope.where("entries.amount < 0")

      # 2. Outflows (positive amount = debit/expense in Sure, excluding non-budget kinds)
      outflows = tx_scope.where("entries.amount > 0")
        .where.not(kind: Transaction::BUDGET_EXCLUDED_KINDS)

      nodes = []
      node_indices = {}
      node_totals = Hash.new(0.0)

      get_or_add_node = ->(id, name, color, initial_val = 0.0) {
        if node_indices.key?(id)
          node_idx = node_indices[id]
          node_totals[id] += initial_val
          node_idx
        else
          node_idx = nodes.size
          node_indices[id] = node_idx
          node_totals[id] = initial_val
          nodes << {
            id: id,
            name: name,
            color: color,
            value: 0.0,
            percentage: 0.0
          }
          node_idx
        end
      }

      links_map = Hash.new { |h, k| h[k] = { value: 0.0, color: nil } }

      total_inflow = 0.0
      total_outflow = 0.0

      # Process Inflows: Income Source -> Destination Account
      inflows.each do |tx|
        account = tx.entry&.account
        next unless account

        amt = tx.entry.amount.abs.to_f
        next if amt <= 0.01

        total_inflow += amt
        income_source_name = tx.merchant&.name.presence || tx.category&.name.presence || "General Inflow"
        source_id = "source_#{income_source_name.parameterize.presence || 'general_inflow'}"
        account_id = "account_#{account.id}"

        src_idx = get_or_add_node.call(source_id, income_source_name, "var(--color-success)", amt)
        tgt_idx = get_or_add_node.call(account_id, account.name, "var(--color-primary)", amt)

        key = [src_idx, tgt_idx]
        links_map[key][:value] += amt
        links_map[key][:color] ||= "var(--color-success)"
      end

      # Process Outflows: Account -> Category -> Merchant
      outflows.each do |tx|
        account = tx.entry&.account
        next unless account

        amt = tx.entry.amount.abs.to_f
        next if amt <= 0.01

        total_outflow += amt
        account_id = "account_#{account.id}"

        category = tx.category
        category_name = category&.name.presence || "Uncategorized"
        category_id = category ? "cat_#{category.id}" : "cat_uncategorized"
        category_color = category&.color.presence || "var(--color-destructive)"

        merchant_name = tx.merchant&.name.presence || "Other Merchants"
        merchant_id = tx.merchant ? "merch_#{tx.merchant.id}" : "merch_other"
        merchant_color = "var(--color-gray-500)"

        acc_idx = get_or_add_node.call(account_id, account.name, "var(--color-primary)", amt)
        cat_idx = get_or_add_node.call(category_id, category_name, category_color, amt)
        merch_idx = get_or_add_node.call(merchant_id, merchant_name, merchant_color, amt)

        # Link: Account -> Category
        acc_cat_key = [acc_idx, cat_idx]
        links_map[acc_cat_key][:value] += amt
        links_map[acc_cat_key][:color] ||= "var(--color-destructive)"

        # Link: Category -> Merchant
        cat_merch_key = [cat_idx, merch_idx]
        links_map[cat_merch_key][:value] += amt
        links_map[cat_merch_key][:color] ||= "var(--color-gray-500)"
      end

      # Build link list
      links = links_map.map do |(src_idx, tgt_idx), data|
        val = data[:value].round(2)
        pct = total_outflow > 0 ? (val / total_outflow * 100.0).round(1) : (total_inflow > 0 ? (val / total_inflow * 100.0).round(1) : 0.0)
        {
          source: src_idx,
          target: tgt_idx,
          value: val,
          color: data[:color],
          percentage: pct
        }
      end

      # Populate calculated node values & percentages
      nodes.each do |node|
        node_id = node[:id]
        val = node_totals[node_id].round(2)
        node[:value] = val
        node[:percentage] = if node_id.start_with?("source_")
          total_inflow > 0 ? (val / total_inflow * 100.0).round(1) : 0.0
        elsif node_id.start_with?("cat_") || node_id.start_with?("merch_")
          total_outflow > 0 ? (val / total_outflow * 100.0).round(1) : 0.0
        else
          # Account node
          tot = total_inflow + total_outflow
          tot > 0 ? (val / tot * 100.0).round(1) : 0.0
        end
      end

      currency_symbol = begin
        Money::Currency.new(family.currency).symbol
      rescue StandardError
        "$"
      end

      {
        nodes: nodes,
        links: links,
        currency_symbol: currency_symbol
      }
    end
  end
end
