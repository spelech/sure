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

tag_cache = {}
family.tags.each { |t| tag_cache[t.name.downcase] = t }

def get_or_create_tags(family, tag_names, cache)
  return [] if tag_names.blank? || !tag_names.is_a?(Array)
  tag_names.map do |raw|
    name = raw.to_s.strip.delete_prefix("#")
    next nil if name.blank?
    cache[name.downcase] ||= family.tags.find_or_create_by!(name: name)
  end.compact
end

stats = {
  total: transactions.size,
  skipped_payroll: 0,
  already_exists: 0,
  enriched_existing: 0,
  created_new: 0,
  receipts_attached: 0,
  tags_applied: 0,
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
    tx_tags = get_or_create_tags(family, tx["tags"], tag_cache)

    date_range = (date - 2.days)..(date + 2.days)
    existing_entry = acc.entries.where(date: date_range)
      .where("abs(entries.amount - ?) < 0.03", sure_amount)
      .order(date: :asc)
      .first

    target_entry = nil

    if existing_entry
      target_entry = existing_entry
      tx_record = existing_entry.entryable
      if tx_record.is_a?(Transaction)
        updated = false
        if tx_record.category_id.blank? && cat.present?
          tx_record.update!(category: cat, merchant: merch || tx_record.merchant)
          updated = true
        end

        tx_tags.each do |tag|
          unless tx_record.tags.include?(tag)
            tx_record.tags << tag
            stats[:tags_applied] += 1
            updated = true
          end
        end

        if updated
          stats[:enriched_existing] += 1
        else
          stats[:already_exists] += 1
        end
      else
        stats[:already_exists] += 1
      end
    else
      begin
        new_tx = Transaction.new(category: cat, merchant: merch)
        target_entry = acc.entries.create!(
          date: date,
          name: tx["clean_name"] || tx["raw_description"],
          amount: sure_amount,
          currency: acc.currency,
          notes: tx["raw_description"],
          external_id: tx["id"],
          entryable: new_tx
        )

        tx_tags.each do |tag|
          new_tx.tags << tag
          stats[:tags_applied] += 1
        end

        stats[:created_new] += 1
      rescue => e
        puts "[reconcile] Error creating transaction: #{e.message}"
        stats[:errors] += 1
      end
    end

    # Attachment logic: attach matched receipt only (not whole monthly statement)
    receipt_path = tx.dig("extra", "receiptPdfPath")
    tx_for_attachment = target_entry&.entryable
    if tx_for_attachment.is_a?(Transaction) && receipt_path.present? && File.exist?(receipt_path)
      fname = File.basename(receipt_path)
      unless tx_for_attachment.attachments.any? { |r| r.filename.to_s == fname }
        begin
          File.open(receipt_path) do |f|
            tx_for_attachment.attachments.attach(
              io: f,
              filename: fname,
              content_type: receipt_path.downcase.end_with?(".png") ? "image/png" : "application/pdf"
            )
          end
          stats[:receipts_attached] += 1
        rescue => e
          puts "[reconcile] Attachment warning for #{fname}: #{e.message}"
        end
      end
    end

    if (idx + 1) % 500 == 0 || idx + 1 == transactions.size
      puts "  [Progress] #{idx + 1}/#{transactions.size} processed..."
    end
  end
end

puts "\n========================================================"
puts "  BANK & CREDIT TRANSACTION RECONCILIATION COMPLETE     "
puts "========================================================"
puts "  Total Evaluated:              #{stats[:total]}"
puts "  Newly Created Historical:     #{stats[:created_new]}"
puts "  Enriched Existing (Tags/Cat): #{stats[:enriched_existing]}"
puts "  Already Existed & Categorized:#{stats[:already_exists]}"
puts "  Tags Applied:                 #{stats[:tags_applied]}"
puts "  Receipts/Docs Attached:       #{stats[:receipts_attached]}"
puts "  Skipped (Handled by Paystub): #{stats[:skipped_payroll]}"
puts "  Errors:                       #{stats[:errors]}"
puts "========================================================"
