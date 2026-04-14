# frozen_string_literal: true

require "open3"
require "tempfile"

module Hunkify
  module Git
    def self.run(cmd)
      stdout, stderr, status = Open3.capture3(cmd)
      raise "Git error: #{stderr.strip}" unless status.success?
      stdout.strip
    end

    def self.staged_diff
      run("git diff --staged")
    end

    def self.staged_files
      run("git diff --staged --name-only").split("\n")
    end

    def self.has_staged_changes?
      !staged_files.empty?
    end

    def self.root
      run("git rev-parse --show-toplevel")
    end

    def self.apply_patch_to_index(patch_content)
      Tempfile.create(["hunkify_patch", ".patch"]) do |f|
        f.write(patch_content)
        f.flush
        stdout, stderr, status = Open3.capture3("git", "apply", "--cached", "--whitespace=nowarn", f.path)
        raise "Git error: #{stderr.strip}" unless status.success?
        stdout.strip
      end
    end

    def self.unstage_all
      if head_exists?
        run("git reset HEAD")
      else
        stdout, _stderr, status = Open3.capture3("git", "ls-files", "-z", "--cached")
        raise "Git error: unable to list index" unless status.success?
        stdout.split("\0").reject(&:empty?).each do |path|
          _o, err, st = Open3.capture3("git", "rm", "--cached", "-f", "--", path)
          raise "Git error: #{err.strip}" unless st.success?
        end
      end
    end

    def self.head_exists?
      _o, _e, status = Open3.capture3("git", "rev-parse", "--verify", "HEAD")
      status.success?
    end

    def self.commit(message)
      stdout, stderr, status = Open3.capture3("git", "commit", "-m", message)
      raise "Git error: #{stderr.strip}" unless status.success?
      stdout.strip
    end

    def self.restage_files(files)
      files.each { |f|
        begin
          run("git add \"#{f}\"")
        rescue
          nil
        end
      }
    end
  end
end
