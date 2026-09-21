# frozen_string_literal: true

require "json"
require_relative "../lib/typesafe/sdk/version"

version = Typesafe::SDK::VERSION
upstream = Typesafe::SDK::UPSTREAM_VERSION
abort "Ruby version must track upstream, optionally followed by a numeric Ruby revision" unless
  version.match?(/\A#{Regexp.escape(upstream)}(?:\.[1-9]\d*)?\z/)

spec = Gem::Specification.load(File.expand_path("../typesafe-sdk-ruby.gemspec", __dir__))
abort "Gemspec version mismatch" unless spec.version.to_s == version
abort "Missing changelog entry" unless File.read(File.expand_path("../CHANGELOG.md",
                                                                  __dir__)).include?("## [#{version}]")

if (tag = ENV.fetch("RELEASE_TAG", nil)) && tag != "v#{version}"
  abort "Tag #{tag.inspect} does not match v#{version}"
end

if ENV.key?("RELEASE_TAG") && !File.read(File.expand_path("../CHANGELOG.md", __dir__))
                                   .match?(/^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}$/)
  abort "Set the changelog release date in a reviewed pull request before tagging"
end

if (manifest = ARGV.first) && JSON.parse(File.read(manifest)).fetch("version") != upstream
  abort "Official JS package version mismatch"
end

puts "Ruby #{version}; official JavaScript SDK #{upstream}"
