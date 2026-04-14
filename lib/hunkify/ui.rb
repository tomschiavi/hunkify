# frozen_string_literal: true

require_relative "color"
require "readline"

module Hunkify
  module UI
    module_function

    def print_header
      version = defined?(Hunkify::VERSION) ? Hunkify::VERSION : ""
      puts
      puts "  #{Color.magenta("▲")} #{Color.bold("hunkify")} #{Color.dim("v#{version}")}"
      puts "  #{Color.dim("─" * 40)}"
      puts "  #{Color.dim("Atomic commits, grouped by Claude.")}"
      puts
    end

    def print_hunks_overview(hunks)
      puts Color.bold("🔍 #{hunks.size} hunk(s) detected:")
      hunks.each do |h|
        added = h.lines.count { |l| l.start_with?("+") }
        removed = h.lines.count { |l| l.start_with?("-") }
        puts "   #{Color.dim("[#{h.id}]")} #{Color.cyan(h.file_path)}  #{Color.green("+#{added}")} #{Color.red("-#{removed}")}"
      end
      puts
    end

    def print_grouping(commits_data, hunks_by_id)
      puts Color.bold("🤖 AI-proposed grouping:")
      puts

      commits_data.each_with_index do |c, i|
        hunk_list = c["hunk_ids"].map { |id| Color.dim("[#{id}]") }.join(" ")
        files = c["hunk_ids"].map { |id| hunks_by_id[id]&.file_path }.compact.uniq

        puts "  #{Color.bold(Color.blue("Commit #{i + 1}"))}  #{hunk_list}"
        puts "  #{Color.green(c["message"])}"
        puts "  #{Color.dim("↳ " + c["reasoning"])}"
        puts "  #{Color.dim("Files: " + files.join(", "))}"
        puts
      end
    end

    def reassign_loop(commits_data, hunks_by_id, context: nil)
      loop do
        print "  #{Color.yellow("[m]")} Move hunk  #{Color.yellow("[n]")} New commit  #{Color.yellow("[Enter]")} Continue  #{Color.yellow("[q]")} Quit: "
        input = $stdin.gets.chomp.downcase

        case input
        when ""
          return
        when "q"
          puts Color.red("\n  Cancelled.")
          exit 0
        when "m"
          move_hunk(commits_data, hunks_by_id, context: context)
        when "n"
          new_commit(commits_data, hunks_by_id, context: context)
        else
          puts Color.dim("  (unknown command)")
        end
      end
    end

    def prompt_new_message(hunk_ids, hunks_by_id, context:)
      hunks = hunk_ids.map { |id| hunks_by_id[id] }.compact
      print Color.dim("  Asking Claude for a suggestion... ")
      begin
        suggestion = AnthropicAPI.suggest_message(hunks, context: context)
      rescue => e
        puts Color.red("failed (#{e.message})")
        suggestion = nil
      end
      puts

      if suggestion && !suggestion.empty?
        puts "  #{Color.dim("suggested:")} #{Color.green(suggestion)}"
        print "  #{Color.yellow("[Enter]")} Accept  #{Color.yellow("[type]")} Override: "
      else
        print "  Commit message: "
      end

      input = $stdin.gets.chomp
      input.empty? ? suggestion : input
    end

    def print_hunk(hunk, max_lines: 25)
      added = hunk.lines.count { |l| l.start_with?("+") }
      removed = hunk.lines.count { |l| l.start_with?("-") }

      title = "Hunk [#{hunk.id}] · #{hunk.file_path}  #{Color.green("+#{added}")} #{Color.red("-#{removed}")}"
      # visible width: strip ANSI to compute padding
      visible = title.gsub(/\e\[[0-9;]*m/, "")
      inner_w = [visible.length + 4, 60].max

      puts
      puts Color.dim("  ╭─ ") + title + " " + Color.dim("─" * [inner_w - visible.length - 4, 1].max) + Color.dim("╮")
      puts Color.dim("  │ ") + Color.dim(hunk.hunk_header)

      lines = hunk.lines
      truncated = lines.size > max_lines
      shown = truncated ? lines.first(max_lines) : lines

      shown.each do |line|
        colored =
          if line.start_with?("+")
            Color.green(line)
          elsif line.start_with?("-")
            Color.red(line)
          else
            line
          end
        puts Color.dim("  │ ") + colored
      end

      if truncated
        puts Color.dim("  │ … #{lines.size - max_lines} more line(s)")
      end

      puts Color.dim("  ╰" + "─" * (inner_w + 2) + "╯")
      puts
    end

    def move_hunk(commits_data, hunks_by_id, context: nil)
      print "  Hunk id? "
      hunk_id = $stdin.gets.chomp.to_i
      unless hunks_by_id.key?(hunk_id)
        puts Color.red("  ✗ Unknown hunk id.")
        return
      end

      print_hunk(hunks_by_id[hunk_id])

      print "  Target commit (1-#{commits_data.size}, 'new', or 'c' to cancel): "
      target = $stdin.gets.chomp.downcase

      if target.empty? || target == "c" || target == "cancel"
        puts Color.dim("  Cancelled.")
        return
      end

      commits_data.each { |c| c["hunk_ids"].delete(hunk_id) }

      if target == "new"
        msg = prompt_new_message([hunk_id], hunks_by_id, context: context)
        if msg.nil? || msg.empty?
          puts Color.red("  ✗ Empty message, reassignment cancelled.")
          reinsert_hunk(commits_data, hunk_id)
          return
        end
        commits_data << {"message" => msg, "hunk_ids" => [hunk_id], "reasoning" => "manual"}
      else
        idx = target.to_i - 1
        unless (0...commits_data.size).cover?(idx)
          puts Color.red("  ✗ Invalid target.")
          reinsert_hunk(commits_data, hunk_id)
          return
        end
        commits_data[idx]["hunk_ids"] << hunk_id
      end

      commits_data.reject! { |c| c["hunk_ids"].empty? }
      puts
      print_grouping(commits_data, hunks_by_id)
    end

    def new_commit(commits_data, hunks_by_id, context: nil)
      print "  Hunk ids (space-separated): "
      ids = $stdin.gets.chomp.split.map(&:to_i)
      ids = ids.select { |id| hunks_by_id.key?(id) }
      if ids.empty?
        puts Color.red("  ✗ No valid hunk ids.")
        return
      end

      msg = prompt_new_message(ids, hunks_by_id, context: context)
      if msg.nil? || msg.empty?
        puts Color.red("  ✗ Empty message, cancelled.")
        return
      end

      commits_data.each { |c| c["hunk_ids"] -= ids }
      commits_data << {"message" => msg, "hunk_ids" => ids, "reasoning" => "manual"}
      commits_data.reject! { |c| c["hunk_ids"].empty? }
      puts
      print_grouping(commits_data, hunks_by_id)
    end

    def prefill_readline(prompt, default)
      Readline.pre_input_hook = lambda do
        Readline.insert_text(" #{default}")
        Readline.redisplay
        Readline.pre_input_hook = nil
      end
      result = Readline.readline(prompt, false)
      result&.sub(/\A /, "")
    end

    def reinsert_hunk(commits_data, hunk_id)
      # Hunk was removed in advance; put it back somewhere safe.
      if commits_data.any?
        commits_data.first["hunk_ids"] << hunk_id
      else
        commits_data << {"message" => "unassigned", "hunk_ids" => [hunk_id], "reasoning" => "manual"}
      end
    end

    def prompt_edit_commit(commit_data, _index, _total)
      print "  #{Color.yellow("[Enter]")} Confirm  #{Color.yellow("[e]")} Edit message  #{Color.yellow("[s]")} Skip  #{Color.yellow("[q]")} Quit: "
      input = $stdin.gets.chomp.downcase

      case input
      when ""
        commit_data["message"]
      when "e"
        new_msg = prefill_readline("  ✏️  New message: ", commit_data["message"])
        new_msg.to_s.empty? ? commit_data["message"] : new_msg
      when "s"
        nil
      when "q"
        puts Color.red("\n  Cancelled.")
        exit 0
      else
        commit_data["message"]
      end
    end

    def confirm_plan(plan)
      puts Color.bold("📋 Final plan:")
      plan.each_with_index do |(msg, _), i|
        puts "   #{Color.dim("#{i + 1}.")} #{Color.green(msg)}"
      end
      puts
      print "  #{Color.yellow("[Enter]")} Run  #{Color.yellow("[q]")} Cancel: "
      input = $stdin.gets.chomp.downcase
      exit 0 if input == "q"
    end
  end
end
