# frozen_string_literal: true

# Usage: bin/rails runner bin/attach_receipts.rb <path_to_manifest.json>

manifest_path = ARGV[0] || "../ledger-ingest/attachment_manifest.json"

unless File.exist?(manifest_path)
  puts "Attachment manifest not found at #{manifest_path}"
  exit 1
end

manifest = JSON.parse(File.read(manifest_path))
puts "Found #{manifest.size} attachment mapping(s) in #{manifest_path}"

attached_count = 0
missing_entry_count = 0
missing_file_count = 0

manifest.each_with_index do |(external_id, file_path), index|
  unless File.exist?(file_path)
    missing_file_count += 1
    next
  end

  entry = Entry.find_by(external_id: external_id)
  unless entry
    missing_entry_count += 1
    next
  end

  # Check if already attached
  filename = File.basename(file_path)
  already_attached = entry.receipts.any? { |r| r.filename.to_s == filename }
  if already_attached
    next
  end

  entry.receipts.attach(
    io: File.open(file_path),
    filename: filename,
    content_type: "application/pdf"
  )
  attached_count += 1

  puts "[#{index + 1}/#{manifest.size}] Attached #{filename} to Entry #{entry.id} (#{entry.name})" if (index + 1) % 50 == 0
end

puts "\n=== Attachment Summary ==="
puts "Successfully attached: #{attached_count}"
puts "Missing entries (not yet imported): #{missing_entry_count}"
puts "Missing files: #{missing_file_count}"
