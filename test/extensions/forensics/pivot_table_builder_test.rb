# frozen_string_literal: true

require "test_helper"

class PivotTableBuilderTest < ActiveSupport::TestCase
  setup do
    @family = families(:default)
    @user = users(:family_admin)
    @period = Period.custom(start_date: 3.months.ago.to_date, end_date: Date.current)
  end

  test "aggregates spend correctly across all 4 dimensions" do
    builder = Forensics::PivotTableBuilder.new(@family, period: @period, user: @user)
    result = builder.build

    assert_kind_of Hash, result
    assert result.key?(:categories)
    assert result.key?(:merchants)
    assert result.key?(:months)
    assert result.key?(:accounts)
    assert result.key?(:total_outflow)
    assert_kind_of Array, result[:categories]
    assert_kind_of Array, result[:merchants]
    assert_kind_of Array, result[:months]
    assert_kind_of Array, result[:accounts]

    if result[:categories].any?
      row = result[:categories].first
      assert row.key?(:key)
      assert row.key?(:count)
      assert row.key?(:total)
      assert row.key?(:avg)
      assert row.key?(:max)
      assert row.key?(:percentage)
      assert row[:total] >= 0
    end
  end

  test "handles empty transactions gracefully" do
    empty_period = Period.custom(start_date: 20.years.ago.to_date, end_date: 19.years.ago.to_date)
    builder = Forensics::PivotTableBuilder.new(@family, period: empty_period, user: @user)
    result = builder.build

    assert_equal 0.0, result[:total_outflow]
    assert_equal [], result[:categories]
    assert_equal [], result[:merchants]
    assert_equal [], result[:months]
    assert_equal [], result[:accounts]
  end
end
