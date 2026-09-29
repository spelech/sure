# frozen_string_literal: true

require "json"

raw_input = if ARGV[0] && File.exist?(ARGV[0])
  File.read(ARGV[0])
else
  STDIN.read
end

rules_data = JSON.parse(raw_input)

family = Family.first
abort("No family found in database") unless family

puts "Syncing #{rules_data.size} rule(s) for family #{family.id}..."

synced = 0
total_matches = 0

ActiveRecord::Base.transaction do
  rules_data.each do |r|
    pattern = r["pattern"]&.strip
    next if pattern.blank?

    rule_name = r["targetMerchant"].presence || pattern
    rule_title = "#{rule_name} Auto-Categorize"

    rule = family.rules.find_or_initialize_by(name: rule_title, resource_type: "transaction")
    rule.active = true
    rule.effective_date = Date.new(2020, 1, 1)

    # Clean existing conditions & actions to avoid duplicate action violations
    rule.conditions.destroy_all
    rule.actions.destroy_all

    # 1. Condition: Transaction name matches pattern
    rule.conditions.build(
      condition_type: "transaction_name",
      operator: "like",
      value: pattern
    )

    # 2. Action: Set Category
    if r["targetCategory"].present?
      category_name = r["targetCategory"].strip
      cat = family.categories.find_or_create_by!(name: category_name) do |c|
        c.color = "#3b82f6"
      end
      rule.actions.build(action_type: "set_transaction_category", value: cat.id.to_s)
    end

    # 3. Action: Set Merchant
    if r["targetMerchant"].present?
      merchant_name = r["targetMerchant"].strip
      merchant = family.merchants.find_or_create_by!(name: merchant_name)
      rule.actions.build(action_type: "set_transaction_merchant", value: merchant.id.to_s)
    end

    # 4. Action: Set Tag (primary tag)
    tags = r["targetTags"]
    tags = JSON.parse(tags) if tags.is_a?(String)
    if tags.is_a?(Array) && tags.any?
      primary_tag_name = tags.first.strip
      if primary_tag_name.present?
        tag = family.tags.find_or_create_by!(name: primary_tag_name) do |t|
          t.color = "#e99537"
        end
        rule.actions.build(action_type: "set_transaction_tags", value: tag.id.to_s)
      end
    end

    rule.save!
    synced += 1
    total_matches += rule.affected_resource_count
  end
end

puts JSON.generate({
  success: true,
  synced_rules: synced,
  total_affected_transactions: total_matches
})
