# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "typesafe-sdk-ruby"
  spec.version = "0.6.0"
  spec.authors = ["TypeSafe Ruby SDK Contributors"]
  spec.email = ["opensource@typesafe.ai"]

  spec.summary = "Unofficial Ruby SDK for the TypeSafe AI API (Jev model)"
  spec.description = <<~DESC.strip
    Unofficial Ruby SDK for the TypeSafe AI API (Jev model). Ask named questions about
    text or structured state and get typed answers: yes/no (noul), choice, and score
    questions, with retries, timeouts, structured logging, and typed errors.
  DESC
  spec.homepage = "https://github.com/afurm/typesafe-sdk-ruby"
  spec.license = "MIT"
  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/afurm/typesafe-sdk-ruby/issues",
    "changelog_uri" => "https://github.com/afurm/typesafe-sdk-ruby/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://docs.typesafe.ai/",
    "homepage_uri" => "https://github.com/afurm/typesafe-sdk-ruby",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/afurm/typesafe-sdk-ruby"
  }

  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"].sort
  spec.require_paths = ["lib"]

  spec.add_dependency "json", ">= 2.7"
end
