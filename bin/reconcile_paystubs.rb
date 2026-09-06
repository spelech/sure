# frozen_string_literal: true
# Usage: bin/rails runner bin/reconcile_paystubs.rb [optional_json_path]
# Or reads from STDIN if no argument provided.

require "json"

raw_input = if ARGV[0] && File.exist?(ARGV[0])
  File.read(ARGV[0])
else
  $stdin.read
end

paystubs = JSON.parse(raw_input)
puts "Loaded #{paystubs.size} paystub record(s) for Sure reconciliation."

family = Family.find_by(name: "823 Spring Cove") || Family.first
puts "Target Family: #{family.name} (id: #{family.id})"

def ensure_category(family, name)
  family.categories.find_or_create_by!(name: name)
end

cat_gross = ensure_category(family, "Income: Gross Pay")
cat_taxes = ensure_category(family, "Taxes: Payroll Withholding")
cat_pretax = ensure_category(family, "Deductions: Pre-Tax & Benefits")
cat_posttax = ensure_category(family, "Deductions: Post-Tax")
cat_reimb = ensure_category(family, "Income: Reimbursements")
cat_transfer = ensure_category(family, "Transfer: Internal")
cat_payroll = ensure_category(family, "Income: Payroll")

checking_account = family.accounts.find_by("name ILIKE ?", "%CHECKING (5750)%") || family.accounts.find_by("name ILIKE ?", "%checking%")
ally_account = family.accounts.find_by("name ILIKE ?", "%Ally%")

unless checking_account
  puts "ERROR: Checking account not found in family."
  exit 1
end

merchant = Merchant.find_or_create_by!(name: "McMaster-Carr")

stats = {
  total: paystubs.size,
  already_split: 0,
  matched_and_split: 0,
  created_and_split: 0,
  receipts_attached: 0,
  errors: 0
}

paystubs.each do |p|
  date = Date.parse(p["checkDate"])
  gross = p["grossPay"].to_d
  taxes = p["taxes"].to_d
  pre_tax = p["preTax"].to_d
  post_tax = p["postTax"].to_d
  reimb = p["reimbursements"].to_d
  net = p["netPay"].to_d
  chase_amt = p["chaseAmount"].to_d
  ally_amt = p["allyAmount"].to_d

  target_account = (chase_amt > 0) ? checking_account : (ally_account || checking_account)
  parent_amount = (chase_amt > 0) ? -chase_amt : -net

  date_range = (date - 4.days)..(date + 4.days)
  existing_entry = target_account.entries.where(date: date_range)
    .where("entries.name ILIKE ? OR entries.name ILIKE ?", "%McMaster%", "%Payroll%")
    .where("abs(entries.amount - ?) < 0.05", parent_amount)
    .order(date: :asc)
    .first

  if existing_entry && existing_entry.child_entries.any?
    stats[:already_split] += 1
    if p["sourceFile"] && File.exist?(p["sourceFile"])
      fname = File.basename(p["sourceFile"])
      unless existing_entry.receipts.any? { |r| r.filename.to_s == fname }
        existing_entry.receipts.attach(io: File.open(p["sourceFile"]), filename: fname, content_type: "application/pdf")
        stats[:receipts_attached] += 1
      end
    end
    next
  end

  splits = [
    { name: "Gross Pay", amount: -gross, category_id: cat_gross.id },
    { name: "Employee Taxes", amount: taxes, category_id: cat_taxes.id }
  ]
  splits << { name: "Pre-Tax Deductions", amount: pre_tax, category_id: cat_pretax.id } if pre_tax > 0
  splits << { name: "Post-Tax Deductions", amount: post_tax, category_id: cat_posttax.id } if post_tax > 0
  splits << { name: "Reimbursements", amount: -reimb, category_id: cat_reimb.id } if reimb.abs > 0.01

  if chase_amt > 0 && ally_amt > 0
    splits << { name: "Transfer to Ally (4855)", amount: ally_amt, category_id: cat_transfer.id }
  end

  split_sum = splits.sum { |s| s[:amount] }
  if (split_sum - parent_amount).abs > 0.02
    delta = parent_amount - split_sum
    splits.first[:amount] += delta
  end

  entry_for_receipt = nil

  if existing_entry
    begin
      existing_entry.split!(splits)
      existing_entry.entryable.update!(merchant: merchant, category: cat_payroll) if existing_entry.entryable.is_a?(Transaction)
      stats[:matched_and_split] += 1
      entry_for_receipt = existing_entry
    rescue => e
      puts "Failed to split existing entry on #{date}: #{e.message}"
      stats[:errors] += 1
      next
    end
  else
    begin
      Entry.transaction do
        tx = Transaction.new(category: cat_payroll, merchant: merchant)
        entry = target_account.entries.create!(
          date: date,
          name: "McMaster-Carr Payroll",
          amount: parent_amount,
          currency: target_account.currency,
          entryable: tx,
          external_id: p["filename"]
        )
        entry.split!(splits)
        stats[:created_and_split] += 1
        entry_for_receipt = entry
      end
    rescue => e
      puts "Failed to create entry on #{date}: #{e.message}"
      stats[:errors] += 1
      next
    end
  end

  if entry_for_receipt && p["sourceFile"] && File.exist?(p["sourceFile"])
    fname = File.basename(p["sourceFile"])
    unless entry_for_receipt.receipts.any? { |r| r.filename.to_s == fname }
      entry_for_receipt.receipts.attach(io: File.open(p["sourceFile"]), filename: fname, content_type: "application/pdf")
      stats[:receipts_attached] += 1
    end
  end
end

puts "\n========================================================"
puts "  PAYSTUB RECONCILIATION & BACKFILL COMPLETE            "
puts "========================================================"
puts "  Total Processed:        #{stats[:total]}"
puts "  Already Up-to-Date:     #{stats[:already_split]}"
puts "  Newly Matched & Split:  #{stats[:matched_and_split]}"
puts "  Newly Created & Split:  #{stats[:created_and_split]}"
puts "  Receipts Attached:      #{stats[:receipts_attached]}"
puts "  Errors / Warnings:      #{stats[:errors]}"
puts "========================================================"
