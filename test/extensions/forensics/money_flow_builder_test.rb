# frozen_string_literal: true

require "test_helper"

class MoneyFlowBuilderTest < ActiveSupport::TestCase
  setup do
    @family = families(:default)
    @user = users(:family_admin)
    @period = Period.custom(start_date: 6.months.ago.to_date, end_date: Date.current)
  end

  test "builds valid multi-tier sankey nodes and links structure" do
    result = Forensics::MoneyFlowBuilder.new(@family, period: @period, user: @user).build

    assert_kind_of Hash, result
    assert result.key?(:nodes)
    assert result.key?(:links)
    assert result.key?(:currency_symbol)
    assert_kind_of Array, result[:nodes]
    assert_kind_of Array, result[:links]
  end

  test "handles empty transactions gracefully" do
    empty_period = Period.custom(start_date: 10.years.ago.to_date, end_date: 9.years.ago.to_date)
    result = Forensics::MoneyFlowBuilder.new(@family, period: empty_period, user: @user).build

    assert_equal [], result[:nodes]
    assert_equal [], result[:links]
    assert_equal Money::Currency.new(@family.currency).symbol, result[:currency_symbol]
  end
end
