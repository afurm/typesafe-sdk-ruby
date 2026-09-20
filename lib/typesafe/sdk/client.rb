# frozen_string_literal: true

require "json"
require "net/http"
require "time"
require "uri"

module Typesafe
  module SDK
    # Default API root.
    DEFAULT_BASE_URL = "https://api.typesafe.ai"
    # Default model used when a request omits `model`.
    DEFAULT_MODEL = "jev-latest"

    # Client for the TypeSafe AI API.
    class Client
      attr_reader :base_url, :default_model, :log_level, :logger, :retry, :timeout,
                  :default_headers, :models

      # Create a client for the TypeSafe AI API.
      #
      # Explicit options take precedence over environment variables, then SDK defaults.
      # Empty or whitespace-only environment values are ignored.
      #
      # @param api_key [String, nil] required unless `TYPESAFE_API_KEY` is set.
      # @param base_url [String, nil] API root; falls back to `TYPESAFE_BASE_URL`.
      # @param default_model [String, nil] falls back to `TYPESAFE_DEFAULT_MODEL`, then `jev-latest`.
      # @param log_level [Symbol, String, nil] falls back to `TYPESAFE_LOG_LEVEL`, then `warn`.
      # @param logger [#debug, #info, #warn, #error] default: {ConsoleLogger}.
      # @param retry_policy [Hash, nil] overrides for {Retry::DEFAULT_RETRY_POLICY}.
      # @param timeout [Float, nil] timeout per attempt in seconds. Default: 10.
      # @param default_headers [Hash, nil] additional request headers.
      # @param http [Object] HTTP adapter responding to `request`. Default: {HTTP}.
      # @raise [TypeSafeError] the API key is missing or configuration is invalid.
      def initialize(api_key: nil, base_url: nil, default_model: nil, log_level: nil,
                     logger: nil, retry_policy: nil, timeout: nil, default_headers: nil,
                     http: nil, env: ::ENV)
        @api_key = ENV.from_code_or_env(api_key, ENV::API_KEY, source: env)
        raise TypeSafeError, missing_api_key_message if @api_key.nil? || @api_key.empty?

        @base_url = strip_trailing_slashes(
          ENV.from_code_or_env(base_url, ENV::BASE_URL, source: env) || DEFAULT_BASE_URL
        )
        @default_model = ENV.from_code_or_env(default_model, ENV::DEFAULT_MODEL, source: env) ||
                         DEFAULT_MODEL
        @log_level = resolve_log_level(log_level, env)
        sink = logger || ConsoleLogger.new
        @logger = LevelLogger.new(sink, @log_level)
        @retry = resolve_retry_policy(Retry::DEFAULT_RETRY_POLICY, retry_policy)
        @timeout = assert_positive("timeout", timeout || Retry::DEFAULT_TIMEOUT_S)
        @default_headers = (default_headers || {}).dup.freeze
        @http = http || HTTP.new
        @models = Resources::Models.new(self)
        @request_count = 0
      end

      # Answer named questions about text or structured state.
      #
      # @param state [String, Hash, Array, nil] the content to evaluate.
      # @param questions [Hash{Symbol, String => Hash}] nonempty questions keyed by name.
      # @param model [String, nil] model override; omitted values inherit `default_model`.
      # @param options [Hash] per-call `timeout`, `retry`, `headers`, and `signal` settings.
      # @return [SystemOneResult] answers keyed by question name, with model and token usage.
      # @raise [TypeSafeError] questions are empty, or score criteria are not a list of at
      #   least two entries.
      # @raise [APIError] the server returns a non-2xx response after retries.
      # @raise [APIConnectionError] the request cannot connect or times out after retries.
      # @raise [APIUserAbortError] the caller cancels the request.
      #
      # @example
      #   response = client.system_one(
      #     state: "I was charged twice. Please help.",
      #     questions: { billing: Typesafe::SDK.noul("Is this about billing?") },
      #   )
      #   response.answers[:billing].noul # => 0.93
      def system_one(state:, questions:, model: nil, **options)
        Questions.validate!(questions)
        body = { state: state, questions: questions, model: model || @default_model }
        response = request(:post, "/v1/systemone", body: body, **options)
        SystemOneResult.new(response.body)
      end

      # Send a request and parse its response body. Internal; used by API resources.
      #
      # @return [Response] the parsed response, with `data`, `status`, `headers`, and `request_id`.
      def request(method, path, body: nil, headers: {}, timeout: nil, retry_policy: nil,
                  signal: nil)
        resolved = {
          method: method,
          path: path,
          body: body,
          headers: merge_headers(@default_headers, headers),
          timeout: timeout.nil? ? @timeout : assert_positive("timeout", timeout),
          retry: resolve_retry_policy(@retry, retry_policy),
          signal: signal
        }
        @request_count += 1
        tag = "##{@request_count} #{method.to_s.upcase} #{path}"
        fetch_with_retries(tag, resolved)
      end

      # The API key, excluded from inspection output.
      def inspect # :nodoc:
        "#<#{self.class.name} base_url=#{@base_url.inspect} default_model=#{@default_model.inspect}>"
      end

      private

      def missing_api_key_message
        "No API key was provided. Pass `api_key:` to Typesafe::SDK::Client.new or set the " \
          "#{ENV::API_KEY} environment variable."
      end

      def resolve_log_level(from_code, env)
        value = from_code || ENV.read(ENV::LOG_LEVEL, source: env) || LogLevel::DEFAULT
        LogLevel.parse!(value, from_code ? "the `log_level` option" : ENV::LOG_LEVEL)
      end

      def strip_trailing_slashes(url)
        url.sub(%r{/+\z}, "")
      end

      def assert_positive(name, value)
        unless value.is_a?(Numeric) && value.positive?
          raise TypeSafeError,
                "`#{name}` must be a positive number, got #{value.inspect}."
        end

        value
      end

      def assert_non_negative_integer(name, value)
        unless value.is_a?(Integer) && value >= 0
          raise TypeSafeError, "`#{name}` must be a non-negative integer, got #{value.inspect}."
        end

        value
      end

      def assert_non_negative(name, value)
        unless value.is_a?(Numeric) && value >= 0
          raise TypeSafeError, "`#{name}` must be a non-negative number, got #{value.inspect}."
        end

        value
      end

      def assert_fraction(name, value)
        unless value.is_a?(Numeric) && value >= 0 && value <= 1
          raise TypeSafeError, "`#{name}` must be between 0 and 1, got #{value.inspect}."
        end

        value
      end

      def assert_status_set(name, statuses)
        statuses.each do |status|
          unless status.is_a?(Integer) && status.between?(100, 999)
            raise TypeSafeError, "`#{name}` must contain HTTP status codes, got #{status.inspect}."
          end
        end
        statuses
      end

      # Merge and validate retry overrides, copying the status list to isolate later mutations.
      def resolve_retry_policy(base, overrides)
        o = overrides || {}
        {
          max_retries: if o.key?(:max_retries)
                         assert_non_negative_integer("retry.max_retries",
                                                     o[:max_retries])
                       else
                         base[:max_retries]
                       end,
          backoff_initial_ms: if o.key?(:backoff_initial_ms)
                                assert_non_negative("retry.backoff_initial_ms",
                                                    o[:backoff_initial_ms])
                              else
                                base[:backoff_initial_ms]
                              end,
          backoff_max_ms: if o.key?(:backoff_max_ms)
                            assert_non_negative("retry.backoff_max_ms",
                                                o[:backoff_max_ms])
                          else
                            base[:backoff_max_ms]
                          end,
          backoff_jitter: if o.key?(:backoff_jitter)
                            assert_fraction("retry.backoff_jitter",
                                            o[:backoff_jitter])
                          else
                            base[:backoff_jitter]
                          end,
          http_statuses: if o.key?(:http_statuses)
                           assert_status_set("retry.http_statuses",
                                             o[:http_statuses].dup)
                         else
                           base[:http_statuses]
                         end,
          respect_retry_after: o.fetch(:respect_retry_after, base[:respect_retry_after]),
          max_retry_after_ms: if o.key?(:max_retry_after_ms)
                                assert_non_negative("retry.max_retry_after_ms",
                                                    o[:max_retry_after_ms])
                              else
                                base[:max_retry_after_ms]
                              end,
          api_connection_error: o.fetch(:api_connection_error, base[:api_connection_error]),
          api_timeout_error: o.fetch(:api_timeout_error, base[:api_timeout_error])
        }.freeze
      end

      # Last value wins regardless of casing; `nil` removes a protected header.
      def merge_headers(*sources)
        merged = {}
        sources.each do |source|
          source.each do |name, value|
            key = name.to_s.downcase
            if value.nil?
              merged.delete(key)
            else
              merged[key] = value
            end
          end
        end
        merged
      end

      # Retry eligible failures, logging attempt summaries at `info` and details at `debug`.
      def fetch_with_retries(tag, req)
        url = "#{@base_url}#{req[:path]}"
        # User-supplied headers go first so they can't clobber auth or the JSON content type.
        headers = merge_headers(req[:headers], {
                                  "Authorization" => "Bearer #{@api_key}",
                                  "Accept" => "application/json",
                                  "User-Agent" => "typesafe-sdk-ruby/#{VERSION}",
                                  "X-TypeSafe-SDK" => "typesafe-sdk-ruby/#{VERSION}",
                                  "X-TypeSafe-Runtime" => "ruby/#{RUBY_VERSION} (#{RUBY_PLATFORM})",
                                  "Content-Type" => req[:body].nil? ? nil : "application/json",
                                  "X-TypeSafe-Retry-Count" => nil
                                })
        payload = req[:body].nil? ? nil : JSON.generate(req[:body])

        attempt = 0
        loop do
          retries_left = req[:retry][:max_retries] - attempt
          attempt_headers = attempt.zero? ? headers : headers.merge("X-TypeSafe-Retry-Count" => attempt.to_s)
          @logger.debug("#{tag} -> #{url}", headers: Redaction.redact_headers(attempt_headers), body: req[:body])

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            response = attempt_request(tag, url, req[:method], attempt_headers, payload, req)
          rescue APIUserAbortError
            raise
          rescue APIConnectionError => e
            raise if retries_left <= 0 || !retryable_connection_error?(e, req[:retry])

            back_off(tag, attempt, retries_left, e.message, nil, req)
            attempt += 1
            next
          end

          request_id = response.request_id
          elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          @logger.info("#{tag} <- #{response.status} in #{elapsed}ms#{" (request #{request_id})" if request_id}")
          return parse_success(tag, response) if response.ok?

          error = APIError.from_response(response.status, response.body, response.headers)
          @logger.debug("#{tag} <- error body", body: response.body)
          raise error if retries_left <= 0 || !Retry.retryable_status?(response.status, req[:retry])

          back_off(tag, attempt, retries_left, response.status.to_s, response.headers, req)
          attempt += 1
        end
      end

      def retryable_connection_error?(error, policy)
        return policy[:api_timeout_error] if error.is_a?(APITimeoutError)

        policy[:api_connection_error]
      end

      def parse_success(tag, response)
        @logger.debug("#{tag} <- body", body: response.body)
        response
      end

      # One HTTP round trip, including body delivery, with a timeout.
      def attempt_request(tag, url, method, headers, payload, req)
        @http.request(
          method: method,
          url: url,
          headers: headers,
          body: payload,
          timeout: req[:timeout],
          signal: req[:signal]
        )
      rescue APIUserAbortError
        raise
      rescue APITimeoutError
        @logger.info("#{tag} timed out")
        raise
      rescue APIConnectionError => e
        @logger.info("#{tag} connection error", error: e.message)
        raise
      end

      # Wait before retrying; caller cancellation raises `APIUserAbortError`.
      def back_off(tag, attempt, retries_left, reason, headers, req)
        delay = Retry.retry_delay_ms(attempt, headers, req[:retry])
        nth = attempt + 1
        total = attempt + retries_left
        @logger.info("#{tag} retrying in #{delay}ms (retry #{nth}/#{total}) after #{reason}")
        sleep_with_signal(delay, req[:signal])
      end

      def sleep_with_signal(seconds, signal)
        signal&.check!
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (seconds / 1000.0)
        loop do
          if signal
            signal.check!
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            signal.wait(remaining) if remaining.positive?
            signal.check!
          else
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            sleep([remaining, 0.1].min)
          end
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        end
      end
    end
  end
end
