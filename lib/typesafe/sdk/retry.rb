# frozen_string_literal: true

module Typesafe
  module SDK
    # Request ID header returned by the API.
    REQUEST_ID_HEADER = "x-typesafe-request-id"

    # Retry defaults, delay calculation, and cancellable waits.
    module Retry
      # Default per-attempt timeout in seconds.
      DEFAULT_TIMEOUT_S = 10

      # Default SDK retry policy.
      DEFAULT_RETRY_POLICY = {
        max_retries: 2,
        backoff_initial_ms: 500,
        backoff_max_ms: 5_000,
        backoff_jitter: 0.25,
        # HTTP 408, 429, and 5xx responses.
        http_statuses: [408, 429, *(500..599)].freeze,
        respect_retry_after: true,
        # Maximum server retry delay before falling back to backoff.
        max_retry_after_ms: 60_000,
        api_connection_error: true,
        api_timeout_error: true
      }.freeze

      module_function

      # Whether the policy retries an HTTP status code.
      def retryable_status?(status, policy = DEFAULT_RETRY_POLICY)
        policy[:http_statuses].include?(status)
      end

      # Parse `retry-after-ms` or `Retry-After` into milliseconds, preferring `retry-after-ms`.
      # Returns `nil` when neither header contains a valid delay.
      def parse_retry_after(headers, now: Time.now)
        return nil unless headers.respond_to?(:[])

        if (ms = headers["retry-after-ms"])
          parsed = Integer(ms, exception: false)
          return parsed if parsed && parsed >= 0
        end

        raw = headers["retry-after"]
        return nil if raw.nil?

        seconds = Float(raw, exception: false)
        return (seconds * 1000).round if seconds && seconds >= 0

        date = begin
          Time.parse(raw)
        rescue StandardError
          nil
        end
        return nil if date.nil?

        [(date - now) * 1000, 0].max.round
      end

      # Calculate the delay in milliseconds for a zero-based retry attempt.
      # Uses an allowed server delay; otherwise capped exponential backoff with jitter.
      def retry_delay_ms(attempt, headers = nil, policy = DEFAULT_RETRY_POLICY, random: Random)
        if policy[:respect_retry_after] && headers
          retry_after = parse_retry_after(headers)
          return retry_after if retry_after && retry_after <= policy[:max_retry_after_ms]
        end

        exponential = [policy[:backoff_initial_ms] * (2**attempt), policy[:backoff_max_ms]].min
        jitter = 1.0 - (random.rand * policy[:backoff_jitter])
        (exponential * jitter).round
      end
    end
  end
end
