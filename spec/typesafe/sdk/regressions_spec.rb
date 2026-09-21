# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"

RSpec.describe "Ruby SDK regressions" do
  let(:http) { instance_double(Typesafe::SDK::HTTP) }
  let(:response) do
    Typesafe::SDK::Response.new(status: 200, headers: Typesafe::SDK::Headers.new({}),
                                body: { "models" => [] }, request_id: "req-1")
  end

  it "works with Ruby Logger at debug level without leaking credentials" do
    output = StringIO.new
    client = Typesafe::SDK::Client.new(api_key: "secret-123456789", http: http,
                                       logger: Logger.new(output), log_level: :debug)
    allow(http).to receive(:request).and_return(response)
    expect(client.models.list).to eq([])
    expect(output.string).to include("headers=", "body=", "Bearer ***6789")
    expect(output.string).not_to include("secret-123456789")
  end

  it "retains structured keyword fields for a structured logger" do
    logger = Typesafe::SDK::ConsoleLogger.new(io: StringIO.new)
    expect(logger).to receive(:debug).with("hello", body: { test: true })
    Typesafe::SDK::LevelLogger.new(logger, :debug).debug("hello", body: { test: true })
  end

  [Float::INFINITY, -Float::INFINITY, Float::NAN, Complex(1, 2)].each do |number|
    it "rejects nonfinite or complex numeric configuration: #{number}" do
      expect { Typesafe::SDK::Client.new(api_key: "k", timeout: number) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /timeout/)
      %i[backoff_initial_ms backoff_max_ms max_retry_after_ms backoff_jitter].each do |field|
        expect { Typesafe::SDK::Client.new(api_key: "k", retry_policy: { field => number }) }
          .to raise_error(Typesafe::SDK::TypeSafeError, /#{field}/)
      end
      client = Typesafe::SDK::Client.new(api_key: "k", http: http)
      expect { client.models.list(timeout: number) }.to raise_error(Typesafe::SDK::TypeSafeError)
      expect(http).not_to receive(:request)
    end
  end

  it "validates questions loaded from JSON before making a request" do
    client = Typesafe::SDK::Client.new(api_key: "k", http: http)
    expect(http).not_to receive(:request)
    expect do
      client.system_one(state: nil, questions: { "rating" => { "type" => "score", "criteria" => ["one"] } })
    end.to raise_error(Typesafe::SDK::TypeSafeError, /at least two scores/)
  end

  it "copies and freezes retry status overrides" do
    statuses = [429]
    client = Typesafe::SDK::Client.new(api_key: "k", retry_policy: { http_statuses: statuses })
    statuses << 400
    expect(client.retry[:http_statuses]).to eq([429])
    expect(client.retry[:http_statuses]).to be_frozen
  end

  it "exposes model-list metadata without changing the ordinary array return" do
    allow(http).to receive(:request).and_return(response)
    client = Typesafe::SDK::Client.new(api_key: "k", http: http)
    result = client.models.list(with_response: true)
    expect(result.data).to eq([])
    expect(result.response).to equal(response)
    expect(result.request_id).to eq("req-1")
    expect(client.models.list).to eq([])
  end

  it "captures an HTTP-date rate-limit delay once" do
    now = Time.utc(2026, 9, 21)
    allow(Time).to receive(:now).and_return(now, now + 10)
    error = Typesafe::SDK::RateLimitError.new(429, {}, Typesafe::SDK::Headers.new("retry-after" => (now + 30).httpdate))
    expect(error.retry_after_ms).to eq(30_000)
    expect(error.retry_after_ms).to eq(30_000)
  end

  it "cancels during backoff without another HTTP attempt" do
    signal = Typesafe::SDK::Signal.new
    headers = Typesafe::SDK::Headers.new("retry-after-ms" => "10000")
    failure = Typesafe::SDK::Response.new(status: 429, headers: headers, body: {}, request_id: nil)
    allow(http).to receive(:request) do
      signal.cancel
      failure
    end
    client = Typesafe::SDK::Client.new(api_key: "k", http: http)
    expect { client.models.list(signal: signal) }.to raise_error(Typesafe::SDK::APIUserAbortError)
    expect(http).to have_received(:request).once
  end

  it "keeps timeout retries independent from connection-error retries" do
    calls = 0
    allow(http).to receive(:request) do
      calls += 1
      raise Typesafe::SDK::APITimeoutError, 100 if calls == 1

      response
    end
    client = Typesafe::SDK::Client.new(api_key: "k", http: http,
                                       retry_policy: { api_connection_error: false, backoff_initial_ms: 0 })
    expect(client.models.list).to eq([])
    expect(calls).to eq(2)
  end
  {
    api_connection_error: Typesafe::SDK::APIConnectionError.new("offline"),
    api_timeout_error: Typesafe::SDK::APITimeoutError.new(100)
  }.each do |flag, error|
    it "inherits disabled #{flag} through a nil per-call override" do
      allow(http).to receive(:request).and_raise(error)
      client = Typesafe::SDK::Client.new(api_key: "k", http: http, retry_policy: { flag => false })
      expect { client.models.list(retry_policy: { flag => nil }) }.to raise_error(error.class)
      expect(http).to have_received(:request).once
    end
  end

  it "inherits respect_retry_after through a nil per-call override" do
    headers = Typesafe::SDK::Headers.new("retry-after-ms" => "123.5")
    failure = Typesafe::SDK::Response.new(status: 429, headers: headers, body: {}, request_id: nil)
    allow(http).to receive(:request).and_return(failure, response)
    client = Typesafe::SDK::Client.new(api_key: "k", http: http)
    expect(client).to receive(:sleep_with_signal).with(123.5, nil)
    expect(client.models.list(retry_policy: { respect_retry_after: nil })).to eq([])
  end
end
