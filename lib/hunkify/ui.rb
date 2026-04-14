# frozen_string_literal: true

require_relative "color"

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

    def prompt_edit_commit(commit_data, _index, _total)
      print "  #{Color.yellow("[Enter]")} Confirm  #{Color.yellow("[e]")} Edit message  #{Color.yellow("[s]")} Skip  #{Color.yellow("[q]")} Quit: "
      input = $stdin.gets.chomp.downcase

      case input
      when ""
        commit_data["message"]
      when "e"
        print "  ✏️  New message: "
        new_msg = $stdin.gets.chomp
        new_msg.empty? ? commit_data["message"] : new_msg
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
