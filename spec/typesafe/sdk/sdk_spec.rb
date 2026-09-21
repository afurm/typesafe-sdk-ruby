# frozen_string_literal: true

require "spec_helper"

RSpec.describe Typesafe::SDK do
  it "exposes the version" do
    expect(Typesafe::SDK::VERSION.split(".").first(3).join("."))
      .to eq(Typesafe::SDK::UPSTREAM_VERSION)
    expect(Gem::Specification.load("typesafe-sdk-ruby.gemspec").version.to_s)
      .to eq(Typesafe::SDK::VERSION)
  end

  describe "top-level builders" do
    it "delegates to Questions" do
      expect(Typesafe::SDK.noul("q?")).to eq(Typesafe::SDK::Questions.noul("q?"))
      expect(Typesafe::SDK.score("q?", %w[a b])).to eq(Typesafe::SDK::Questions.score("q?", %w[a b]))
      expect(Typesafe::SDK.choice("q?", a: nil)).to eq(Typesafe::SDK::Questions.choice("q?", a: nil))
    end
  end

  describe Typesafe::SDK::Headers do
    it "looks up headers case-insensitively" do
      headers = described_class.new("X-Typesafe-Request-Id" => "abc")
      expect(headers["x-typesafe-request-id"]).to eq("abc")
      expect(headers["X-Typesafe-Request-Id"]).to eq("abc")
      expect(headers.key?("X-TYPESAFE-REQUEST-ID")).to be(true)
    end
  end

  describe Typesafe::SDK::Redaction do
    it "redacts authorization headers, keeping the scheme and key tail" do
      redacted = described_class.redact_headers(
        "Authorization" => "Bearer sk-1234567890abcdef",
        "Cookie" => "session=secret",
        "X-Custom" => "visible"
      )
      expect(redacted["Authorization"]).to eq("Bearer ***cdef")
      expect(redacted["Cookie"]).to eq("***")
      expect(redacted["X-Custom"]).to eq("visible")
    end
  end
end
