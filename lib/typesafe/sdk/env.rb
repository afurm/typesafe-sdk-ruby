# frozen_string_literal: true

module Typesafe
  module SDK
    # Environment variable names for client configuration. Explicit options take precedence.
    module ENV
      # Required API key; used when `api_key` is omitted.
      API_KEY = "TYPESAFE_API_KEY"
      # API root; defaults to `https://api.typesafe.ai`.
      BASE_URL = "TYPESAFE_BASE_URL"
      # Default model name; defaults to `jev-latest`.
      DEFAULT_MODEL = "TYPESAFE_DEFAULT_MODEL"
      # Log level; defaults to `warn`.
      LOG_LEVEL = "TYPESAFE_LOG_LEVEL"

      ALL = [API_KEY, BASE_URL, DEFAULT_MODEL, LOG_LEVEL].freeze

      module_function

      # Read a trimmed environment value, returning `nil` for missing or blank values.
      def read(name, source: ::ENV)
        value = source[name].to_s.strip
        value.empty? ? nil : value
      end

      # Return the explicit value, falling back to the environment.
      def from_code_or_env(from_code, name, source: ::ENV)
        from_code || read(name, source: source)
      end
    end
  end
end
