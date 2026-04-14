# frozen_string_literal: true

module Hunkify
  Hunk = Struct.new(:id, :file_header, :file_path, :hunk_header, :lines, keyword_init: true) do
    def to_patch
      body = lines.join("\n")
      body += "\n" unless body.end_with?("\n")
      "#{file_header}\n#{hunk_header}\n#{body}"
    end

    def to_summary
      added = lines.count { |l| l.start_with?("+") }
      removed = lines.count { |l| l.start_with?("-") }
      preview = lines.first(6).join("\n")
      "[HUNK #{id}] #{file_path} #{hunk_header}\n#{preview}\n(+#{added} / -#{removed} lines)"
    end
  end
end
