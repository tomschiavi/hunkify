# frozen_string_literal: true

module Hunkify
  module Color
    RESET = "\e[0m"
    BOLD = "\e[1m"
    DIM = "\e[2m"
    CYAN = "\e[36m"
    GREEN = "\e[32m"
    YELLOW = "\e[33m"
    RED = "\e[31m"
    MAGENTA = "\e[35m"
    BLUE = "\e[34m"

    def self.cyan(s) = "#{CYAN}#{s}#{RESET}"
    def self.green(s) = "#{GREEN}#{s}#{RESET}"
    def self.yellow(s) = "#{YELLOW}#{s}#{RESET}"
    def self.red(s) = "#{RED}#{s}#{RESET}"
    def self.bold(s) = "#{BOLD}#{s}#{RESET}"
    def self.dim(s) = "#{DIM}#{s}#{RESET}"
    def self.magenta(s) = "#{MAGENTA}#{s}#{RESET}"
    def self.blue(s) = "#{BLUE}#{s}#{RESET}"
  end
end
