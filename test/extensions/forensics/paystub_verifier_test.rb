# frozen_string_literal: true

require "test_helper"

class PaystubVerifierTest < ActiveSupport::TestCase
  setup do
    @family = Family.create!(name: "Test Forensic Family", currency: "USD")
    @user = @family.users.create!(
      email: "forensic_test_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "admin"
    )
    @account = @family.accounts.create!(
      name: "Checking (1234)",
      currency: "USD",
      balance: 1000,
      accountable: Depository.new,
      status: "active"
    )

    @cat_payroll = @family.categories.create!(name: "Income: Payroll", color: "#10b981")
    @cat_gross = @family.categories.create!(name: "Income: Gross Pay", color: "#10b981")
    @cat_taxes = @family.categories.create!(name: "Taxes: Payroll Withholding", color: "#ef4444")
    @cat_pretax = @family.categories.create!(name: "Deductions: Pre-Tax & Benefits", color: "#f59e0b")

    @merchant = @family.merchants.create!(name: "McMaster-Carr")

    @period = Period.custom(start_date: 30.days.ago.to_date, end_date: Date.current)
  end

  teardown do
    @family.destroy
  end

  test "correctly classifies reconciled deposit with splits and attached PDF" do
    tx = Transaction.new(category: @cat_payroll, merchant: @merchant)
    entry = @account.entries.create!(
      date: 5.days.ago.to_date,
      name: "McMaster-Carr Payroll",
      amount: -2500.00,
      currency: "USD",
      entryable: tx
    )

    # Attach mock PDF to Transaction
    tx.attachments.attach(
      io: StringIO.new("%PDF-1.4 mock paystub content"),
      filename: "paystub_2026_09.pdf",
      content_type: "application/pdf"
    )

    # Split into gross, taxes, and deductions
    entry.split!([
      { name: "Gross Pay", amount: -3500.00, category_id: @cat_gross.id },
      { name: "Federal Taxes", amount: 700.00, category_id: @cat_taxes.id },
      { name: "Pre-Tax 401k", amount: 300.00, category_id: @cat_pretax.id }
    ])

    result = Forensics::PaystubVerifier.new(@family, period: @period, user: @user).build

    assert_equal 1, result[:payroll_count]
    assert_equal 1, result[:reconciled_count]
    assert_equal 0, result[:unreconciled_count]
    assert_equal 2500.00, result[:total_inflow]
    assert_equal 3500.00, result[:total_gross]
    assert_equal 700.00, result[:total_taxes]
    assert_equal 300.00, result[:total_deductions]

    payroll_item = result[:payrolls].first
    assert_equal "reconciled", payroll_item[:status]
    assert_equal true, payroll_item[:has_attachment]
    assert_equal true, payroll_item[:is_split]
    assert_includes payroll_item[:attachment_names], "paystub_2026_09.pdf"
    assert_equal 3500.00, payroll_item[:gross_pay]
    assert_equal 700.00, payroll_item[:taxes]
    assert_equal 300.00, payroll_item[:pre_tax]
  end

  test "correctly identifies split-only and unattached deposit statuses" do
    # 1. Split-only deposit (no PDF attachment)
    tx1 = Transaction.new(category: @cat_payroll, merchant: @merchant)
    entry1 = @account.entries.create!(
      date: 10.days.ago.to_date,
      name: "McMaster-Carr Payroll",
      amount: -2000.00,
      currency: "USD",
      entryable: tx1
    )
    entry1.split!([
      { name: "Gross Pay", amount: -2800.00, category_id: @cat_gross.id },
      { name: "Employee Taxes", amount: 800.00, category_id: @cat_taxes.id }
    ])

    # 2. Raw unattached deposit (no split, no PDF)
    tx2 = Transaction.new(category: @cat_payroll, merchant: @merchant)
    @account.entries.create!(
      date: 15.days.ago.to_date,
      name: "Employer Direct Deposit",
      amount: -1500.00,
      currency: "USD",
      entryable: tx2
    )

    result = Forensics::PaystubVerifier.new(@family, period: @period, user: @user).build

    assert_equal 2, result[:payroll_count]
    assert_equal 0, result[:reconciled_count]
    assert_equal 2, result[:unreconciled_count]
    assert_equal 3500.00, result[:total_inflow]

    statuses = result[:payrolls].map { |p| p[:status] }
    assert_includes statuses, "split_only"
    assert_includes statuses, "unattached_deposit"
  end

  test "handles empty period without crashing" do
    empty_period = Period.custom(start_date: 10.years.ago.to_date, end_date: 9.years.ago.to_date)
    result = Forensics::PaystubVerifier.new(@family, period: empty_period, user: @user).build

    assert_equal 0.0, result[:total_inflow]
    assert_equal 0, result[:payroll_count]
    assert_equal 0, result[:reconciled_count]
    assert_equal [], result[:payrolls]
  end
end
