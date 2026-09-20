# frozen_string_literal: true

require "spec_helper"

RSpec.describe Typesafe::SDK::APIError do
  def headers_with(request_id: nil, extra: {})
    raw = { "content-type" => "application/json" }.merge(extra)
    raw["x-typesafe-request-id"] = request_id if request_id
    Typesafe::SDK::Headers.new(raw)
  end

  describe ".from_response" do
    it "maps status codes to subclasses" do
      expect(described_class.from_response(400, {}, headers_with)).to be_a(Typesafe::SDK::BadRequestError)
      expect(described_class.from_response(401, {}, headers_with)).to be_a(Typesafe::SDK::AuthenticationError)
      expect(described_class.from_response(403, {}, headers_with)).to be_a(Typesafe::SDK::PermissionDeniedError)
      expect(described_class.from_response(404, {}, headers_with)).to be_a(Typesafe::SDK::NotFoundError)
      expect(described_class.from_response(422, {}, headers_with)).to be_a(Typesafe::SDK::UnprocessableEntityError)
      expect(described_class.from_response(429, {}, headers_with)).to be_a(Typesafe::SDK::RateLimitError)
      expect(described_class.from_response(500, {}, headers_with)).to be_a(Typesafe::SDK::InternalServerError)
      expect(described_class.from_response(503, {}, headers_with)).to be_a(Typesafe::SDK::InternalServerError)
      expect(described_class.from_response(409, {}, headers_with)).to be_a(described_class)
    end

    it "extracts messages from common body shapes" do
      expect(described_class.from_response(400, { "error" => "bad" }, headers_with).message)
        .to eq("400 bad")
      expect(described_class.from_response(400, { "message" => "nope" }, headers_with).message)
        .to eq("400 nope")
      expect(described_class.from_response(400, { "detail" => "why" }, headers_with).message)
        .to eq("400 why")
      expect(described_class.from_response(400, { "error" => { "message" => "inner" } }, headers_with).message)
        .to eq("400 inner")
    end

    it "formats validation error arrays" do
      body = { "detail" => [{ "loc" => %w[body questions], "msg" => "must not be empty" }] }
      expect(described_class.from_response(422, body, headers_with).message)
        .to eq("422 questions: must not be empty")
    end

    it "truncates long raw bodies" do
      body = { "noise" => "x" * 500 }
      message = described_class.from_response(400, body, headers_with).message
      expect(message.length).to be < 250
      expect(message).to end_with("…")
    end

    it "captures the request id" do
      error = described_class.from_response(500, {}, headers_with(request_id: "req-123"))
      expect(error.request_id).to eq("req-123")
    end
  end

  describe Typesafe::SDK::RateLimitError do
    it "exposes retry_after_ms" do
      headers = Typesafe::SDK::Headers.new("retry-after-ms" => "300")
      error = described_class.new(429, {}, headers)
      expect(error.retry_after_ms).to eq(300)
    end
  end

  describe Typesafe::SDK::APITimeoutError do
    it "reports the timeout" do
      error = described_class.new(10_000)
      expect(error.message).to eq("Request timed out after 10000ms.")
      expect(error.timeout_ms).to eq(10_000)
      expect(error).to be_a(Typesafe::SDK::APIConnectionError)
    end
  end
end
