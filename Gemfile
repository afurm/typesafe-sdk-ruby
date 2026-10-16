# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "logger", require: false
  gem "rake"
  gem "rspec", "~> 3.13"
  gem "rubocop", require: false
  gem "simplecov", require: false
  gem "webmock", "~> 3.24"
  # Optional at runtime; enables zstd request compression and its specs.
  gem "zstd-ruby", "~> 2.0", require: false
end
