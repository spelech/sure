# frozen_string_literal: true

require "test_helper"

class TemporalHeatmapBuilderTest < ActiveSupport::TestCase
  setup do
    @family = families(:default)
    @user = users(:family_admin)
  end

  test "generates daily spending points across 365 days" do
    builder = Forensics::TemporalHeatmapBuilder.new(@family, user: @user)
    result = builder.build

    assert_kind_of Hash, result
    assert result.key?(:days)
    assert_operator result[:days].size, :>=, 365
    assert result.key?(:top_merchants)
    assert result.key?(:total_year_spend)
    assert result.key?(:currency_symbol)
    assert_kind_of Array, result[:days]
    assert_kind_of Array, result[:top_merchants]
    assert_kind_of Float, result[:total_year_spend]
    assert_kind_of String, result[:currency_symbol]
  end

  test "validates day points structure and attributes" do
    builder = Forensics::TemporalHeatmapBuilder.new(@family, user: @user)
    result = builder.build

    first_day = result[:days].first
    assert first_day.key?(:date)
    assert first_day.key?(:day_of_week)
    assert first_day.key?(:month)
    assert first_day.key?(:year)
    assert first_day.key?(:total)
    assert first_day.key?(:count)

    assert_includes 0..6, first_day[:day_of_week]
    assert_includes 1..12, first_day[:month]
    assert_kind_of Float, first_day[:total]
    assert_kind_of Integer, first_day[:count]
  end

  test "extracts top merchants with daily totals" do
    builder = Forensics::TemporalHeatmapBuilder.new(@family, user: @user)
    result = builder.build

    assert result[:top_merchants].size <= 20
    if result[:top_merchants].any?
      merchant = result[:top_merchants].first
      assert merchant.key?(:id)
      assert merchant.key?(:name)
      assert merchant.key?(:total)
      assert merchant.key?(:count)
      assert merchant.key?(:daily_totals)
      assert_kind_of Hash, merchant[:daily_totals]
      assert merchant[:total] >= 0
    end
  end

  test "handles empty family transactions gracefully" do
    empty_family = Family.create!(name: "Empty Test Family", currency: "USD")
    builder = Forensics::TemporalHeatmapBuilder.new(empty_family)
    result = builder.build

    assert_operator result[:days].size, :>=, 365
    assert_equal 0.0, result[:total_year_spend]
    assert_equal [], result[:top_merchants]
    assert_equal "$", result[:currency_symbol]
    assert result[:days].all? { |d| d[:total] == 0.0 && d[:count] == 0 }
  end
end
