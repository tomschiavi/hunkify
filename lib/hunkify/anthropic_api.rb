# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Hunkify
  module AnthropicAPI
    API_URL = "https://api.anthropic.com/v1/messages"
    MODEL = "claude-haiku-4-5-20251001"

    SYSTEM_PROMPT = <<~PROMPT
      You are a Git expert. You are given a list of hunks (blocks of modifications)
      extracted from a git diff. Your job is to group them into coherent logical commits.

      GROUPING RULES:
      - One commit = one unique intent (feat, fix, refactor, style, etc.)
      - Hunks in different files CAN belong to the same commit if they serve the same intent
      - Hunks in the SAME file can belong to DIFFERENT commits if they are semantically distinct
      - Prefer atomic and independent commits

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

    def self.group_hunks(hunks, context: nil)
      api_key = ENV["ANTHROPIC_API_KEY"]
      raise "ANTHROPIC_API_KEY missing! Add it to your ~/.zshrc or ~/.bashrc" if api_key.nil? || api_key.empty?

      user_ctx = context && !context.empty? ? "\nUser context: #{context}" : ""
      hunks_summary = hunks.map(&:to_summary).join("\n\n---\n\n")
      user_message = "#{user_ctx}\n\nHere are the hunks to group:\n\n#{hunks_summary}"

      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = api_key
      request["anthropic-version"] = "2023-06-01"
      request.body = JSON.generate({
        model: MODEL,
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: [{role: "user", content: user_message}]
      })

      response = http.request(request)
      body = JSON.parse(response.body)

      raise "API Error #{response.code}: #{body["error"]&.dig("message")}" unless response.code == "200"

      raw = body.dig("content", 0, "text")&.strip

      if ENV["HUNKIFY_DEBUG"]
        warn "\n--- RAW AI RESPONSE ---\n#{raw}\n-----------------------\n"
      end

      cleaned = raw
        .gsub(/\A```(?:json)?\s*/i, "")
        .gsub(/\s*```\z/, "")
        .strip

      if (match = cleaned.match(/(\{.+\})/m))
        cleaned = match[1]
      end

      JSON.parse(cleaned)
    end

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

    def self.suggest_message(hunks, context: nil)
      api_key = ENV["ANTHROPIC_API_KEY"]
      raise "ANTHROPIC_API_KEY missing!" if api_key.nil? || api_key.empty?

      user_ctx = context && !context.empty? ? "\nUser context: #{context}" : ""
      summary = hunks.map(&:to_summary).join("\n\n---\n\n")
      user_message = "#{user_ctx}\n\nHunks to bundle into a single commit:\n\n#{summary}"

      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = api_key
      request["anthropic-version"] = "2023-06-01"
      request.body = JSON.generate({
        model: MODEL,
        max_tokens: 128,
        system: SUGGEST_SYSTEM_PROMPT,
        messages: [{role: "user", content: user_message}]
      })

      response = http.request(request)
      body = JSON.parse(response.body)
      raise "API Error #{response.code}: #{body["error"]&.dig("message")}" unless response.code == "200"

      body.dig("content", 0, "text").to_s.strip.lines.first.to_s.strip
    end
  end
end
