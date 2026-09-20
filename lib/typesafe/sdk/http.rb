# frozen_string_literal: true

require "net/http"

module Typesafe
  module SDK
    # A cancellation handle for requests. Thread-safe; call {#cancel} from another thread.
    class Signal
      def initialize
        @mutex = Mutex.new
        @canceled = false
      end

      def canceled?
        @mutex.synchronize { @canceled }
      end

      def cancel
        @mutex.synchronize { @canceled = true }
      end

      # Raise {APIUserAbortError} if canceled.
      def check!
        raise APIUserAbortError if canceled?
      end

      # Wait up to `seconds`, returning early when canceled.
      def wait(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        while !canceled? && (remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
          sleep([remaining, 0.05].min)
        end
      end
    end

    # A parsed HTTP response.
    class Response
      attr_reader :status, :headers, :body, :request_id

      def initialize(status:, headers:, body:, request_id:)
        @status = status
        @headers = headers
        @body = body
        @request_id = request_id
      end

      def ok?
        status.between?(200, 299)
      end
    end

    # The default HTTP adapter built on `Net::HTTP`.
    #
    # Replace it by passing `http:` to {Client} with any object responding to `request`
    # that returns a {Response} and raises {APIConnectionError}, {APITimeoutError}, or
    # {APIUserAbortError} on failure.
    class HTTP
      # Perform one HTTP round trip.
      #
      # @param method [Symbol] `:get` or `:post`.
      # @param url [String] absolute URL.
      # @param headers [Hash{String => String}] request headers.
      # @param body [String, nil] JSON-encoded request body.
      # @param timeout [Numeric] timeout in seconds.
      # @param signal [Signal, nil] cancellation handle.
      # @return [Response]
      def request(method:, url:, headers:, body:, timeout:, signal:)
        uri = URI(url)
        check_signal!(signal)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout if http.respond_to?(:write_timeout=)

        request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post }.fetch(method)
        req = request_class.new(uri.request_uri)
        headers.each { |name, value| req[name] = value }
        req.body = body if body

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = http.request(req)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        body_text = raw.body.to_s
        parsed = parse_body(body_text, raw["content-type"])
        Response.new(
          status: raw.code.to_i,
          headers: Headers.new(raw.each_header.to_h),
          body: parsed,
          request_id: raw["x-typesafe-request-id"]
        )
      rescue APIUserAbortError
        raise
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
        raise APITimeoutError.new((timeout * 1000).round, cause: e)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
             SocketError, OpenSSL::SSL::SSLError, EOFError, IOError => e
        raise APIConnectionError.new("Connection error: #{e.message}", cause: e)
      end

      private

      def check_signal!(signal)
        signal&.check!
      end

      def parse_body(text, content_type)
        return nil if text.empty?

        if content_type.to_s.include?("application/json")
          begin
            return JSON.parse(text)
          rescue JSON::ParserError
            return text
          end
        end
        # Be lenient: servers and proxies don't always set content-type.
        begin
          JSON.parse(text)
        rescue JSON::ParserError
          text
        end
      end
    end

    # Case-insensitive header lookup, matching the JS SDK's `Headers` semantics.
    class Headers
      def initialize(hash)
        @hash = hash.to_h { |k, v| [k.to_s.downcase, v] }
      end

      def [](name)
        @hash[name.to_s.downcase]
      end

      def key?(name)
        @hash.key?(name.to_s.downcase)
      end

      def to_h
        @hash.dup
      end

      def each(&)
        @hash.each(&)
      end

      def ==(other)
        @hash == (other.is_a?(Headers) ? other.to_h : other)
      end
    end
  end
end
