# frozen_string_literal: true

require_relative "hunk"

module Hunkify
  module DiffParser
    def self.parse(raw_diff)
      hunks = []
      hunk_id = 0
      file_header = nil
      file_path = nil
      hunk_header = nil
      hunk_lines = []

      raw_diff.each_line do |line|
        line = line.chomp
        line = " " if line.empty? && hunk_header

        if line.start_with?("diff --git")
          if hunk_header && !hunk_lines.empty?
            hunk_id += 1
            hunks << Hunk.new(
              id: hunk_id,
              file_header: file_header,
              file_path: file_path,
              hunk_header: hunk_header,
              lines: hunk_lines.dup
            )
          end
          hunk_header = nil
          hunk_lines = []
          file_header = line
          file_path = line.split(" b/").last

        elsif line.start_with?("--- ", "+++ ", "index ", "new file", "deleted file", "old mode", "new mode", "rename ")
          file_header = "#{file_header}\n#{line}"

        elsif line.start_with?("@@")
          if hunk_header && !hunk_lines.empty?
            hunk_id += 1
            hunks << Hunk.new(
              id: hunk_id,
              file_header: file_header,
              file_path: file_path,
              hunk_header: hunk_header,
              lines: hunk_lines.dup
            )
          end
          hunk_header = line
          hunk_lines = []

        elsif hunk_header
          hunk_lines << line
        end
      end

      if hunk_header && !hunk_lines.empty?
        hunk_id += 1
        hunks << Hunk.new(
          id: hunk_id,
          file_header: file_header,
          file_path: file_path,
          hunk_header: hunk_header,
          lines: hunk_lines.dup
        )
      end

      hunks
    end
  end
end
