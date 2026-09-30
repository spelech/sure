# frozen_string_literal: true

require "test_helper"

class MoneyFlowBuilderTest < ActiveSupport::TestCase
  setup do
    @family = Family.create!(name: "Test Forensic Family Money", currency: "USD")
    @user = @family.users.create!(
      email: "forensic_flow_#{SecureRandom.hex(4)}@example.com",
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
    @cat_groceries = @family.categories.create!(name: "Groceries", color: "#3b82f6")
    @cat_utilities = @family.categories.create!(name: "Utilities", color: "#f59e0b")

    @merch_employer = @family.merchants.create!(name: "McMaster-Carr")
    @merch_jewel = @family.merchants.create!(name: "Jewel-Osco")
    @merch_comed = @family.merchants.create!(name: "ComEd")
    @merch_minor1 = @family.merchants.create!(name: "Corner Deli")
    @merch_minor2 = @family.merchants.create!(name: "Local Cafe")

    @period = Period.custom(start_date: 30.days.ago.to_date, end_date: Date.current)
  end

  teardown do
    @family.destroy
  end

  test "builds valid DAG structure with correct link-to-node index mapping" do
    # 1. Inflow: $3,000 from Employer -> Checking
    @account.entries.create!(
      date: 5.days.ago.to_date,
      name: "Payroll Deposit",
      amount: -3000.00,
      currency: "USD",
      entryable: Transaction.new(category: @cat_payroll, merchant: @merch_employer)
    )

    # 2. Outflows
    @account.entries.create!(
      date: 4.days.ago.to_date,
      name: "Groceries Run",
      amount: 450.00,
      currency: "USD",
      entryable: Transaction.new(category: @cat_groceries, merchant: @merch_jewel)
    )

    @account.entries.create!(
      date: 3.days.ago.to_date,
      name: "Electric Bill",
      amount: 150.00,
      currency: "USD",
      entryable: Transaction.new(category: @cat_utilities, merchant: @merch_comed)
    )

    result = Forensics::MoneyFlowBuilder.new(@family, period: @period, user: @user).build

    assert_kind_of Hash, result
    nodes = result[:nodes]
    links = result[:links]

    assert_equal 3000.00, result[:total_inflow]
    assert_equal 600.00, result[:total_outflow]
    assert_operator nodes.size, :>, 0
    assert_operator links.size, :>, 0

    # Verify every link has valid source and target within nodes array bounds
    links.each_with_index do |link, idx|
      assert_operator link[:source], :>=, 0, "Link #{idx} source underflow"
      assert_operator link[:source], :<, nodes.size, "Link #{idx} source out of bounds"
      assert_operator link[:target], :>=, 0, "Link #{idx} target underflow"
      assert_operator link[:target], :<, nodes.size, "Link #{idx} target out of bounds"
      assert_operator link[:value], :>, 0, "Link #{idx} value non-positive"
      assert_not_equal link[:source], link[:target], "Link #{idx} is circular"
    end

    # Verify node structure
    node_ids = nodes.map { |n| n[:id] }
    assert_includes node_ids, "account_#{@account.id}"
    assert_includes node_ids, "cat_#{@cat_groceries.id}"
    assert_includes node_ids, "cat_#{@cat_utilities.id}"
  end

  test "handles period with no transactions cleanly" do
    empty_period = Period.custom(start_date: 10.years.ago.to_date, end_date: 9.years.ago.to_date)
    result = Forensics::MoneyFlowBuilder.new(@family, period: empty_period, user: @user).build

    assert_equal [], result[:nodes]
    assert_equal [], result[:links]
    assert_equal 0.0, result[:total_inflow]
    assert_equal 0.0, result[:total_outflow]
  end
end
