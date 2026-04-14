# frozen_string_literal: true

require_relative "color"
require_relative "diff_parser"
require_relative "git"
require_relative "anthropic_api"
require_relative "ui"

module SmartCommit
  module CLI
    module_function

    def run(argv)
      context = argv[0]

      UI.print_header

      begin
        Git.root
      rescue RuntimeError
        puts Color.red("  ✗ This directory is not a Git repository.")
        exit 1
      end

      unless Git.has_staged_changes?
        puts Color.yellow("  ⚠️  No staged changes.")
        puts Color.dim("  Run first: git add <files>")
        exit 0
      end

      original_staged_files = Git.staged_files

      puts Color.dim("  Parsing diff...")
      raw_diff = Git.staged_diff
      hunks = DiffParser.parse(raw_diff)

      if hunks.empty?
        puts Color.yellow("  ⚠️  No hunks found in staged diff.")
        exit 0
      end

      UI.print_hunks_overview(hunks)

      hunks_by_id = hunks.each_with_object({}) { |h, acc| acc[h.id] = h }

      puts Color.dim("  Analyzing and grouping via Claude #{AnthropicAPI::MODEL}...")
      puts

      begin
        result = AnthropicAPI.group_hunks(hunks, context: context)
      rescue JSON::ParserError
        puts Color.red("  ✗ Invalid AI response (malformed JSON). Try again.")
        exit 1
      rescue RuntimeError => e
        puts Color.red("  ✗ #{e.message}")
        exit 1
      end

      commits_data = result["commits"]

      if commits_data.nil? || commits_data.empty?
        puts Color.red("  ✗ The AI returned no commits.")
        exit 1
      end

      commits_data.each do |c|
        c["hunk_ids"] = c["hunk_ids"].select { |id| hunks_by_id.key?(id) }
      end
      commits_data.reject! { |c| c["hunk_ids"].empty? }

      UI.print_grouping(commits_data, hunks_by_id)

      plan = []
      commits_data.each_with_index do |c, i|
        puts Color.bold("  Commit #{i + 1}/#{commits_data.size}:")
        msg = UI.prompt_edit_commit(c, i + 1, commits_data.size)
        plan << [msg, c["hunk_ids"]] if msg
        puts
      end

      if plan.empty?
        puts Color.yellow("  No commit selected.")
        exit 0
      end

      UI.confirm_plan(plan)

      execute_commits(plan, hunks_by_id, original_staged_files)

      puts
      puts Color.bold(Color.green("  ✅ #{plan.size} commit(s) successfully created!"))
      puts
    end

    def execute_commits(plan, hunks_by_id, original_staged_files)
      puts
      total = plan.size

      Git.unstage_all

      plan.each_with_index do |(message, hunk_ids), i|
        print "  #{Color.dim("Commit #{i + 1}/#{total}...")} "

        hunks_by_file = hunk_ids
          .map { |id| hunks_by_id[id] }
          .group_by(&:file_path)

        patch = hunks_by_file.map do |_file_path, file_hunks|
          first = file_hunks.first
          hunk_bodies = file_hunks.map do |h|
            body = h.lines.join("\n")
            body += "\n" unless body.end_with?("\n")
            "#{h.hunk_header}\n#{body}"
          end.join
          "#{first.file_header}\n#{hunk_bodies}"
        end.join("\n")

        if ENV["SMART_COMMIT_DEBUG"]
          warn "\n--- PATCH ---\n#{patch}\n-------------\n"
        end

        begin
          Git.apply_patch_to_index(patch)
          Git.commit(message)
          puts Color.green("✓ #{message}")
        rescue RuntimeError => e
          puts Color.red("✗ #{e.message}")
          puts Color.yellow("  ⚠️  Rollback: restaging original files...")
          Git.unstage_all
          Git.restage_files(original_staged_files)
          raise
        end
      end
    end
  end
end
