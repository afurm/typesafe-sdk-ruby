# frozen_string_literal: true

module Typesafe
  module SDK
    # Base class for SDK errors.
    class TypeSafeError < StandardError
      def initialize(message = nil, cause: nil)
        super(message)
        @cause = cause
      end

      attr_reader :cause
    end

    # An unsuccessful HTTP response from the API.
    class APIError < TypeSafeError
      MAX_RAW_BODY_IN_MESSAGE = 200

      # HTTP response status code.
      attr_reader :status
      # HTTP response headers (a case-insensitive hash).
      attr_reader :headers
      # Parsed JSON, response text, or `nil` for an empty body.
      attr_reader :body
      # Request ID from `x-typesafe-request-id`, or `nil` when absent.
      attr_reader :request_id

      def initialize(status, body, headers, message = nil)
        super(message || APIError.describe(status, body))
        @status = status
        @body = body
        @headers = headers
        @request_id = headers[Typesafe::SDK::REQUEST_ID_HEADER]
      end

      def self.describe(status, body)
        detail = extract_message(body)
        return "#{status} #{detail}" if detail
        return "#{status} status code (no body)" if body.nil?

        raw = body.is_a?(String) ? body : JSON.generate(body)
        raw = "#{raw[0, MAX_RAW_BODY_IN_MESSAGE]}…" if raw.length > MAX_RAW_BODY_IN_MESSAGE
        "#{status} #{raw}"
      end

      # Create the error subclass for an HTTP status code.
      def self.from_response(status, body, headers)
        klass = status_classes[status]
        klass ||= InternalServerError if status >= 500
        return klass.new(status, body, headers) if klass

        new(status, body, headers)
      end

      def self.status_classes
        @status_classes ||= {
          400 => Typesafe::SDK::BadRequestError,
          401 => Typesafe::SDK::AuthenticationError,
          403 => Typesafe::SDK::PermissionDeniedError,
          404 => Typesafe::SDK::NotFoundError,
          422 => Typesafe::SDK::UnprocessableEntityError,
          429 => Typesafe::SDK::RateLimitError
        }.freeze
      end

      def self.extract_message(body)
        return body if body.is_a?(String) && !body.empty?
        return nil unless body.is_a?(Hash)

        error = body["error"]
        return error if error.is_a?(String)
        return error["message"] if error.is_a?(Hash) && error["message"].is_a?(String)
        return body["message"] if body["message"].is_a?(String)
        return body["detail"] if body["detail"].is_a?(String)
        return body["detail"]["message"] if body["detail"].is_a?(Hash) && body["detail"]["message"].is_a?(String)
        return describe_validation_errors(body["detail"]) if body["detail"].is_a?(Array)

        nil
      end

      # Format validation errors as semicolon-separated `path: message` entries.
      def self.describe_validation_errors(errors)
        parts = errors.filter_map do |e|
          next nil unless e.is_a?(Hash) && e["msg"].is_a?(String)

          loc = e["loc"].is_a?(Array) ? e["loc"].reject { |x| x == "body" }.join(".") : ""
          loc.empty? ? e["msg"] : "#{loc}: #{e['msg']}"
        end
        parts.empty? ? nil : parts.join("; ")
      end
    end

    # HTTP 400: the request is invalid.
    class BadRequestError < APIError; end
    # HTTP 401: authentication failed.
    class AuthenticationError < APIError; end
    # HTTP 403: access is denied.
    class PermissionDeniedError < APIError; end
    # HTTP 404: the resource was not found.
    class NotFoundError < APIError; end
    # HTTP 422: request validation failed.
    class UnprocessableEntityError < APIError; end

    # HTTP 429: the rate limit was exceeded.
    class RateLimitError < APIError
      # Captured at response time, so HTTP-date delays do not change between reads.
      attr_reader :retry_after_ms

      def initialize(...)
        super
        @retry_after_ms = Typesafe::SDK::Retry.parse_retry_after(@headers)
      end
    end

    # HTTP 5xx: the server failed to handle the request.
    class InternalServerError < APIError; end

    # The request or response-body delivery failed (DNS, TLS, connection closed, etc.).
    class APIConnectionError < TypeSafeError
      def initialize(message = "Connection error.", cause: nil)
        super
      end
    end

    # The full response did not arrive within the timeout. A kind of `APIConnectionError`.
    class APITimeoutError < APIConnectionError
      # Configured timeout in milliseconds.
      attr_reader :timeout_ms

      def initialize(timeout_ms, cause: nil)
        super("Request timed out after #{timeout_ms}ms.", cause: cause)
        @timeout_ms = timeout_ms
      end
    end

    # The caller cancelled the request.
    class APIUserAbortError < TypeSafeError
      def initialize(message = "Request was aborted.", cause: nil)
        super
      end
    end
  end
end
