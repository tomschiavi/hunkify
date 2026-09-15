# frozen_string_literal: true

require "json"
require "open3"

module Hunkify
  module OpenCode
    MODEL = "github-copilot/gpt-5.6-terra"

    SYSTEM_PROMPT = <<~PROMPT
      You are a Git expert. You are given a list of hunks (blocks of modifications)
      extracted from a git diff. Your job is to group them into coherent logical commits.

      GROUPING RULES:
      - One commit = one unique intent (feat, fix, refactor, style, etc.)
      - Hunks in different files CAN belong to the same commit if they serve the same intent
      - Hunks in the SAME file can belong to DIFFERENT commits if they are semantically distinct
      - STRONGLY prefer fine-grained, atomic commits over large bundled ones.
        When in doubt, SPLIT rather than merge.
      - Heuristics to split:
        * Different modules/components/features → different commits
        * Core logic vs. tests → different commits (one feat commit + one test commit)
        * Core logic vs. docs → different commits
        * Core logic vs. config/build files → different commits
        * Unrelated fixes bundled with a feature → separate them
        * Each file introducing a new, independent capability usually deserves
          its own commit
      - Only bundle hunks together when they genuinely cannot be reviewed or
        reverted independently.
      - Err on the side of MORE commits. A PR with 8 small focused commits is
        better than one with 3 large ones.

      RESPONSE FORMAT (strict JSON, no surrounding text):
      {
        "commits": [
          {
            "message": ":sparkles: feat(scope): description in English",
            "hunk_ids": [1, 3, 5],
            "reasoning": "brief explanation of the grouping"
          },
          {
            "message": ":bug: fix(scope): description in English",
            "hunk_ids": [2, 4],
            "reasoning": "brief explanation"
          }
        ]
      }

      AVAILABLE GITMOJIS:
      :sparkles: feat | :bug: fix | :recycle: refactor | :lipstick: style
      :white_check_mark: test | :memo: docs | :wrench: config | :package: build
      :zap: perf | :lock: security | :fire: remove | :art: format
      :construction: wip | :card_file_box: db | :green_heart: ci | :rocket: deploy

      MESSAGE RULES:
      - In English, imperative, no leading capital, no trailing period
      - Max 72 characters
      - Scope = module / component / main file concerned
      - If a user context is provided, use it as a hint to steer scope, wording,
        or grouping. It may be a ticket ID (include it as the scope, e.g. feat(EA4-370): ...),
        a feature name, or a free-form directive.

      RESPOND ONLY WITH THE JSON. No markdown, no explanation.
    PROMPT

    SUGGEST_SYSTEM_PROMPT = <<~PROMPT
      You are a Git expert. You are given one or more hunks that the user wants
      to bundle into a single commit. Produce ONE conventional commit message
      following these rules:

      - Gitmoji + type + scope: ":sparkles: feat(scope): short description"
      - Types: feat, fix, refactor, style, test, docs, config, build, perf, security
      - In English, imperative, no leading capital, no trailing period
      - Max 72 characters
      - If a user context is provided, use it to steer scope/wording. If it looks
        like a ticket ID, use it as the scope.

      AVAILABLE GITMOJIS:
      :sparkles: feat | :bug: fix | :recycle: refactor | :lipstick: style
      :white_check_mark: test | :memo: docs | :wrench: config | :package: build
      :zap: perf | :lock: security

      RESPOND ONLY WITH THE MESSAGE. No markdown, no quotes, no explanation.
    PROMPT

    def self.group_hunks(hunks, context: nil)
      user_ctx = context && !context.empty? ? "\nUser context: #{context}" : ""
      summary = hunks.map(&:to_summary).join("\n\n---\n\n")
      raw = ask(SYSTEM_PROMPT, "#{user_ctx}\n\nHere are the hunks to group:\n\n#{summary}")
      cleaned = raw.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
      cleaned = Regexp.last_match(1) if cleaned.match(/(\{.+\})/m)
      JSON.parse(cleaned)
    end

    def self.suggest_message(hunks, context: nil)
      user_ctx = context && !context.empty? ? "\nUser context: #{context}" : ""
      summary = hunks.map(&:to_summary).join("\n\n---\n\n")
      ask(SUGGEST_SYSTEM_PROMPT, "#{user_ctx}\n\nHunks to bundle into a single commit:\n\n#{summary}").lines.first.to_s.strip
    end

    def self.ask(system_prompt, user_message)
      output, status = Open3.capture2e("opencode", "run", "--model", MODEL, "--format", "json", "#{system_prompt}\n\n#{user_message}")
      raise "OpenCode failed: #{output.strip}" unless status.success?

      raw = output.lines.filter_map do |line|
        event = JSON.parse(line)
        event.dig("part", "text") if event["type"] == "text"
      rescue JSON::ParserError
        nil
      end.join.strip

      raise "OpenCode returned no text response" if raw.empty?

      warn "\n--- RAW AI RESPONSE ---\n#{raw}\n-----------------------\n" if ENV["HUNKIFY_DEBUG"]
      raw
    end
  end
end
