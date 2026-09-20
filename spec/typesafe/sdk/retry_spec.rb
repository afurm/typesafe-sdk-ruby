# frozen_string_literal: true

require "spec_helper"

RSpec.describe Typesafe::SDK::Retry do
  let(:policy) { described_class::DEFAULT_RETRY_POLICY }

  describe ".retryable_status?" do
    it "retries 408, 429, and 5xx" do
      expect(described_class.retryable_status?(408, policy)).to be(true)
      expect(described_class.retryable_status?(429, policy)).to be(true)
      expect(described_class.retryable_status?(500, policy)).to be(true)
      expect(described_class.retryable_status?(599, policy)).to be(true)
    end

    it "does not retry other statuses" do
      expect(described_class.retryable_status?(400, policy)).to be(false)
      expect(described_class.retryable_status?(401, policy)).to be(false)
      expect(described_class.retryable_status?(404, policy)).to be(false)
      expect(described_class.retryable_status?(422, policy)).to be(false)
    end
  end

  describe ".parse_retry_after" do
    it "prefers retry-after-ms" do
      headers = Typesafe::SDK::Headers.new("retry-after-ms" => "250", "retry-after" => "9")
      expect(described_class.parse_retry_after(headers)).to eq(250)
    end

    it "parses numeric Retry-After seconds" do
      headers = Typesafe::SDK::Headers.new("retry-after" => "2")
      expect(described_class.parse_retry_after(headers)).to eq(2000)
    end

    it "parses HTTP-date Retry-After" do
      future = Time.now + 5
      headers = Typesafe::SDK::Headers.new("retry-after" => future.httpdate)
      expect(described_class.parse_retry_after(headers)).to be_between(3000, 5000)
    end

    it "returns nil for missing or invalid headers" do
      expect(described_class.parse_retry_after(Typesafe::SDK::Headers.new({}))).to be_nil
      expect(described_class.parse_retry_after(Typesafe::SDK::Headers.new("retry-after" => "soon")))
        .to be_nil
    end
  end

  describe ".retry_delay_ms" do
    it "uses the server delay when allowed" do
      headers = Typesafe::SDK::Headers.new("retry-after-ms" => "750")
      expect(described_class.retry_delay_ms(0, headers, policy, random: Random.new(1))).to eq(750)
    end

    it "falls back to backoff when the server delay exceeds the cap" do
      headers = Typesafe::SDK::Headers.new("retry-after-ms" => "120000")
      delay = described_class.retry_delay_ms(0, headers, policy, random: Random.new(1))
      expect(delay).to be_between(375, 500)
    end

    it "doubles backoff up to the cap" do
      random = Object.new
      def random.rand(*)
        0.0
      end
      delay4 = described_class.retry_delay_ms(4, nil, policy, random: random)
      expect(delay4).to eq(5000)
    end

    it "applies jitter below the exponential delay" do
      delay0 = described_class.retry_delay_ms(0, nil, policy, random: Random.new(42))
      expect(delay0).to be_between(375, 500)
    end
  end
end
