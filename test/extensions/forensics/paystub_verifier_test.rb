# frozen_string_literal: true

require "test_helper"

class PaystubVerifierTest < ActiveSupport::TestCase
  setup do
    @family = families(:default)
    @user = users(:family_admin)
    @period = Period.custom(start_date: 6.months.ago.to_date, end_date: Date.current)
  end

  test "identifies payroll inflows and computes summary metrics" do
    verifier = Forensics::PaystubVerifier.new(@family, period: @period, user: @user)
    result = verifier.build

    assert_kind_of Hash, result
    assert result.key?(:total_inflow)
    assert result.key?(:payroll_count)
    assert result.key?(:avg_paycheck)
    assert result.key?(:accounts_count)
    assert result.key?(:payrolls)
    assert result.key?(:currency_symbol)

    assert_kind_of Float, result[:total_inflow]
    assert_kind_of Integer, result[:payroll_count]
    assert_kind_of Float, result[:avg_paycheck]
    assert_kind_of Integer, result[:accounts_count]
    assert_kind_of Array, result[:payrolls]
    assert_kind_of String, result[:currency_symbol]

    if result[:payrolls].any?
      payroll = result[:payrolls].first
      assert payroll.key?(:id)
      assert payroll.key?(:date)
      assert payroll.key?(:employer)
      assert payroll.key?(:account_name)
      assert payroll.key?(:account_type)
      assert payroll.key?(:amount)
      assert payroll.key?(:status)
      assert payroll[:amount] >= 0
    end
  end

  test "handles empty transactions gracefully" do
    empty_period = Period.custom(start_date: 20.years.ago.to_date, end_date: 19.years.ago.to_date)
    verifier = Forensics::PaystubVerifier.new(@family, period: empty_period, user: @user)
    result = verifier.build

    assert_equal 0.0, result[:total_inflow]
    assert_equal 0, result[:payroll_count]
    assert_equal 0.0, result[:avg_paycheck]
    assert_equal 0, result[:accounts_count]
    assert_equal [], result[:payrolls]
    assert_equal Money::Currency.new(@family.currency).symbol, result[:currency_symbol]
  end
end
