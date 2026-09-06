# frozen_string_literal: true
# Usage: bin/rails runner bin/reconcile_bank_transactions.rb [json_path]
require "json"

raw_input = if ARGV[0] && File.exist?(ARGV[0])
  File.read(ARGV[0])
else
  $stdin.read
end

transactions = JSON.parse(raw_input)
puts "Loaded #{transactions.size} bank/credit transaction(s) to reconcile."

family = Family.find_by(name: "823 Spring Cove") || Family.first
puts "Target Family: #{family.name}"

# Accounts
acc_chase_credit = family.accounts.find_by("name ILIKE ?", "%2219%") || family.accounts.find_by("name ILIKE ?", "%Sapphire%")
acc_chase_checking = family.accounts.find_by("name ILIKE ?", "%5750%") || family.accounts.find_by("name ILIKE ?", "%checking%")
acc_ally = family.accounts.find_by("name ILIKE ?", "%Ally%")

unless acc_ally
  depository = Depository.create!(subtype: "checking")
  acc_ally = family.accounts.create!(
    name: "Ally Interest Checking",
    accountable: depository,
    currency: "USD",
    balance: 0
  )
end

account_map = {
  "chase-credit" => acc_chase_credit,
  "chase-checking" => acc_chase_checking,
  "ally-checking" => acc_ally
}

category_cache = {}
family.categories.each { |c| category_cache[c.name.downcase] = c }

def get_or_create_category(family, name, cache)
  return nil if name.blank? || name == "Unknown"
  clean = name.strip
  cache[clean.downcase] ||= family.categories.find_or_create_by!(name: clean)
end

merchant_cache = {}
family.merchants.each { |m| merchant_cache[m.name.downcase] = m }

def get_or_create_merchant(family, name, cache)
  return nil if name.blank? || name == "Unknown"
  clean = name.strip
  cache[clean.downcase] ||= family.merchants.find_or_create_by!(name: clean)
end

stats = {
  total: transactions.size,
  skipped_payroll: 0,
  already_exists_categorized: 0,
  updated_existing_category: 0,
  created_new: 0,
  errors: 0
}

Entry.transaction do
  transactions.each_with_index do |tx, idx|
    acc = account_map[tx["account_id"]]
    unless acc
      stats[:skipped_payroll] += 1
      next
    end

    if tx["account_id"] == "checking-account"
      stats[:skipped_payroll] += 1
      next
    end

    date = Date.parse(tx["date"])
    amt = tx["amount"].to_d
    sure_amount = amt

    cat = get_or_create_category(family, tx["category_name"], category_cache)
    merch = get_or_create_merchant(family, tx["merchant_name"] || tx["clean_name"], merchant_cache)

    date_range = (date - 2.days)..(date + 2.days)
    existing_entry = acc.entries.where(date: date_range)
      .where("abs(entries.amount - ?) < 0.03", sure_amount)
      .order(date: :asc)
      .first

    if existing_entry
      tx_record = existing_entry.entryable
      if tx_record.is_a?(Transaction)
        if tx_record.category_id.blank? && cat.present?
          tx_record.update!(category: cat, merchant: merch || tx_record.merchant)
          stats[:updated_existing_category] += 1
        else
          stats[:already_exists_categorized] += 1
        end
      else
        stats[:already_exists_categorized] += 1
      end
    else
      begin
        new_tx = Transaction.new(category: cat, merchant: merch)
        acc.entries.create!(
          date: date,
          name: tx["clean_name"] || tx["raw_description"],
          amount: sure_amount,
          currency: acc.currency,
          notes: tx["raw_description"],
          external_id: tx["id"],
          entryable: new_tx
        )
        stats[:created_new] += 1
      rescue => e
        stats[:errors] += 1
      end
    end
  end
end

puts "\n========================================================"
puts "  BANK & CREDIT TRANSACTION RECONCILIATION COMPLETE     "
puts "========================================================"
puts "  Total Evaluated:              #{stats[:total]}"
puts "  Newly Created Historical:     #{stats[:created_new]}"
puts "  Updated Existing Category:    #{stats[:updated_existing_category]}"
puts "  Already Existed & Categorized:#{stats[:already_exists_categorized]}"
puts "  Skipped (Handled by Paystub): #{stats[:skipped_payroll]}"
puts "  Errors:                       #{stats[:errors]}"
puts "========================================================"
