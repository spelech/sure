# frozen_string_literal: true

require "test_helper"

class TemporalHeatmapBuilderTest < ActiveSupport::TestCase
  setup do
    @family = Family.create!(name: "Test Forensic Family Heatmap", currency: "USD")
    @user = @family.users.create!(
      email: "forensic_heatmap_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "admin"
    )
    @account = @family.accounts.create!(
      name: "Credit Card (3333)",
      currency: "USD",
      balance: 1000,
      accountable: CreditCard.new,
      status: "active"
    )

    @cat_shopping = @family.categories.create!(name: "Shopping", color: "#3b82f6")
    @cat_gas = @family.categories.create!(name: "Transportation", color: "#f59e0b")

    @merch_target = @family.merchants.create!(name: "Target")
    @merch_shell = @family.merchants.create!(name: "Shell")
  end

  teardown do
    @family.destroy
  end

  test "generates 365 calendar days and correctly populates target date totals" do
    target_date = 5.days.ago.to_date
    shell_date = 10.days.ago.to_date

    @account.entries.create!(
      date: target_date,
      name: "Target Run",
      amount: 120.50,
      currency: "USD",
      entryable: Transaction.new(category: @cat_shopping, merchant: @merch_target)
    )

    @account.entries.create!(
      date: shell_date,
      name: "Shell Gas",
      amount: 45.25,
      currency: "USD",
      entryable: Transaction.new(category: @cat_gas, merchant: @merch_shell)
    )

    result = Forensics::TemporalHeatmapBuilder.new(@family, user: @user).build

    assert_kind_of Hash, result
    assert_operator result[:days].size, :>=, 365
    assert_equal 165.75, result[:total_year_spend]

    day_map = result[:days].index_by { |d| d[:date] }

    target_day = day_map[target_date.iso8601]
    assert_not_nil target_day, "Target date entry missing from heatmap days"
    assert_equal 120.50, target_day[:total]
    assert_equal 1, target_day[:count]

    shell_day = day_map[shell_date.iso8601]
    assert_not_nil shell_day, "Shell date entry missing from heatmap days"
    assert_equal 45.25, shell_day[:total]
    assert_equal 1, shell_day[:count]

    # Verify top merchants aggregation
    merch_map = result[:top_merchants].index_by { |m| m[:name] }
    assert_equal 120.50, merch_map["Target"][:total]
    assert_equal 45.25, merch_map["Shell"][:total]
  end
end
