# frozen_string_literal: true

module Typesafe
  module SDK
    # Log verbosity; `off` disables logging.
    module LogLevel
      DEBUG = :debug
      INFO = :info
      WARN = :warn
      ERROR = :error
      OFF = :off

      LEVELS = [DEBUG, INFO, WARN, ERROR, OFF].freeze
      DEFAULT = WARN

      RANK = { DEBUG => 0, INFO => 1, WARN => 2, ERROR => 3, OFF => 4 }.freeze

      module_function

      # Validate a configured log level, raising {Typesafe::SDK::TypeSafeError} for unknown values.
      def parse!(value, source)
        return value if LEVELS.include?(value)
        return value.to_sym if value.is_a?(String) && LEVELS.include?(value.to_sym)

        raise Typesafe::SDK::TypeSafeError,
              "Invalid log level #{value.inspect} from #{source}. " \
              "Expected one of: #{LEVELS.join(', ')}."
      end
    end

    # Default logger writing to `$stderr` with the `[typesafe-ai]` prefix.
    class ConsoleLogger
      PREFIX = "[typesafe-ai]"

      def initialize(io: $stderr)
        @io = io
      end

      %i[debug info warn error].each do |severity|
        define_method(severity) do |message, **data|
          @io.puts("#{PREFIX} #{severity.upcase}: #{message}#{format_data(data)}")
        end
      end

      private

      def format_data(data)
        return "" if data.empty?

        " #{data.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')}"
      end
    end

    # Filter logger calls to the configured level and above.
    class LevelLogger
      attr_reader :sink

      def initialize(sink, level)
        @sink = sink
        @rank = LogLevel::RANK.fetch(level)
      end

      %i[debug info warn error].each do |severity|
        define_method(severity) do |message, **data|
          return if LogLevel::RANK.fetch(severity) < @rank

          @sink.public_send(severity, message, **data)
        end
      end
    end

    # Credential headers that retain a key suffix for identification.
    module Redaction
      KEY_HEADERS = %w[authorization proxy-authorization x-api-key].freeze
      OPAQUE_HEADERS = %w[cookie set-cookie].freeze

      module_function

      # Mask a key, preserving its scheme and the last four characters of secrets longer than eight.
      def redact_key(value)
        scheme, secret = value.include?(" ") ? value.split(/\s+/, 2) : [nil, value]
        tail = secret && secret.length > 8 ? secret[-4..] : ""
        "#{"#{scheme} " if scheme}***#{tail}"
      end

      def redact(name, value)
        lower = name.downcase
        return redact_key(value) if KEY_HEADERS.include?(lower)
        return "***" if OPAQUE_HEADERS.include?(lower)

        value
      end

      # Copy headers with known credential values redacted.
      def redact_headers(headers)
        headers.to_h { |name, value| [name, redact(name, value)] }
      end
    end
  end
end
