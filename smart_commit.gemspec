# frozen_string_literal: true

require_relative "lib/smart_commit/version"

Gem::Specification.new do |spec|
  spec.name = "smart_commit"
  spec.version = SmartCommit::VERSION
  spec.authors = ["Tom SCHIAVI"]
  spec.summary = "Split staged changes into atomic commits using Claude."
  spec.description = "smart_commit analyzes staged hunks, asks Claude to group them into logical commits, and applies them via git apply --cached."
  spec.license = "MIT"
  spec.homepage = "https://github.com/tomschiavi/smartcommit"

  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "LICENSE"]
  spec.bindir = "bin"
  spec.executables = ["smart_commit"]
  spec.require_paths = ["lib"]
end
