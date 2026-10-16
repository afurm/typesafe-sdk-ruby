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

          if data.empty? || @sink.method(severity).parameters.any? { |kind, _| %i[key keyreq keyrest].include?(kind) }
            @sink.public_send(severity, message, **data)
          else
            @sink.public_send(severity, "#{message} #{data.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')}")
          end
        end
      end
    end

    # Credential headers that retain a key suffix for identification.
    module Redaction
      KEY_HEADERS = %w[authorization proxy-authorization x-api-key].freeze
      # Headers whose values may start with an authentication scheme such as `Bearer`.
      SCHEME_HEADERS = %w[authorization proxy-authorization].freeze
      OPAQUE_HEADERS = %w[cookie set-cookie].freeze
      # An alphabetic scheme followed by a nonempty credential (RFC 9110 §11.4).
      SCHEMED = /\A([A-Za-z]+)[ \t]+(\S.*)\z/m

      module_function

      # Mask a key, keeping the last four characters of secrets longer than eight. An alphabetic
      # leading scheme, such as `Bearer`, is kept only when `scheme` is true and a credential
      # follows it; otherwise the whole value is masked, so a secret is never shown as a scheme.
      def redact_key(value, scheme: true)
        value = value.to_s
        match = scheme ? SCHEMED.match(value) : nil
        prefix, secret = match ? ["#{match[1]} ", match[2].strip] : ["", value.strip]
        tail = secret.length > 8 ? secret[-4..] : ""
        "#{prefix}***#{tail}"
      end

      def redact(name, value)
        lower = name.downcase
        return redact_key(value, scheme: SCHEME_HEADERS.include?(lower)) if KEY_HEADERS.include?(lower)
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
