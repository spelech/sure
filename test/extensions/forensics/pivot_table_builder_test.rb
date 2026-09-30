# frozen_string_literal: true

require "test_helper"

class PivotTableBuilderTest < ActiveSupport::TestCase
  setup do
    @family = Family.create!(name: "Test Forensic Family Pivot", currency: "USD")
    @user = @family.users.create!(
      email: "forensic_pivot_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "admin"
    )
    @account1 = @family.accounts.create!(
      name: "Checking (1111)",
      currency: "USD",
      balance: 1000,
      accountable: Depository.new,
      status: "active"
    )
    @account2 = @family.accounts.create!(
      name: "Credit Card (2222)",
      currency: "USD",
      balance: 1000,
      accountable: CreditCard.new,
      status: "active"
    )

    @cat_groceries = @family.categories.create!(name: "Groceries", color: "#3b82f6")
    @cat_utilities = @family.categories.create!(name: "Utilities", color: "#f59e0b")

    @merch_jewel = @family.merchants.create!(name: "Jewel-Osco")
    @merch_aldi = @family.merchants.create!(name: "ALDI")
    @merch_comed = @family.merchants.create!(name: "ComEd")

    @period = Period.custom(start_date: 30.days.ago.to_date, end_date: Date.current)
  end

  teardown do
    @family.destroy
  end

  test "accurately computes metrics across Category, Merchant, and Account dimensions" do
    # 1. $100 at Jewel on Account 1 (Groceries)
    @account1.entries.create!(
      date: 5.days.ago.to_date,
      name: "Jewel Run",
      amount: 100.00,
      currency: "USD",
      entryable: Transaction.new(category: @cat_groceries, merchant: @merch_jewel)
    )

    # 2. $50 at ALDI on Account 1 (Groceries)
    @account1.entries.create!(
      date: 4.days.ago.to_date,
      name: "ALDI Trip",
      amount: 50.00,
      currency: "USD",
      entryable: Transaction.new(category: @cat_groceries, merchant: @merch_aldi)
    )

    # 3. $200 at ComEd on Account 2 (Utilities)
    @account2.entries.create!(
      date: 3.days.ago.to_date,
      name: "ComEd Electric",
      amount: 200.00,
      currency: "USD",
      entryable: Transaction.new(category: @cat_utilities, merchant: @merch_comed)
    )

    result = Forensics::PivotTableBuilder.new(@family, period: @period, user: @user).build

    assert_equal 350.00, result[:total_outflow]

    # Verify Categories
    cat_map = result[:categories].index_by { |c| c[:key] }
    assert_equal 150.00, cat_map["Groceries"][:total]
    assert_equal 2, cat_map["Groceries"][:count]
    assert_equal 75.00, cat_map["Groceries"][:avg]
    assert_equal 100.00, cat_map["Groceries"][:max]

    assert_equal 200.00, cat_map["Utilities"][:total]
    assert_equal 1, cat_map["Utilities"][:count]
    assert_equal 200.00, cat_map["Utilities"][:avg]
    assert_equal 200.00, cat_map["Utilities"][:max]

    # Verify Merchants
    merch_map = result[:merchants].index_by { |m| m[:key] }
    assert_equal 100.00, merch_map["Jewel-Osco"][:total]
    assert_equal 50.00, merch_map["ALDI"][:total]
    assert_equal 200.00, merch_map["ComEd"][:total]

    # Verify Accounts
    acc_map = result[:accounts].index_by { |a| a[:key] }
    assert_equal 150.00, acc_map[@account1.name][:total]
    assert_equal 200.00, acc_map[@account2.name][:total]

    # Percentage sum check
    cat_pct_sum = result[:categories].sum { |c| c[:percentage] }.round(1)
    assert_in_delta 100.0, cat_pct_sum, 0.5
  end

  test "handles empty periods cleanly" do
    empty_period = Period.custom(start_date: 10.years.ago.to_date, end_date: 9.years.ago.to_date)
    result = Forensics::PivotTableBuilder.new(@family, period: empty_period, user: @user).build

    assert_equal 0.0, result[:total_outflow]
    assert_equal [], result[:categories]
    assert_equal [], result[:merchants]
  end
end
