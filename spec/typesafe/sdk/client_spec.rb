# frozen_string_literal: true

require "spec_helper"

RSpec.describe Typesafe::SDK::Client do
  let(:env) { { "TYPESAFE_API_KEY" => "test-key" } }
  let(:http) { instance_double(Typesafe::SDK::HTTP) }
  let(:client) do
    described_class.new(api_key: "test-key", http: http, env: env, logger: NullLogger.new)
  end

  class NullLogger
    %i[debug info warn error].each { |m| define_method(m) { |*, **| } }
  end

  def response(status, body, headers = {})
    Typesafe::SDK::Response.new(
      status: status,
      headers: Typesafe::SDK::Headers.new(headers),
      body: body,
      request_id: headers["x-typesafe-request-id"]
    )
  end

  describe "#initialize" do
    it "raises without an API key" do
      expect { described_class.new(env: {}) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /No API key was provided/)
    end

    it "reads the key from the environment" do
      client = described_class.new(env: { "TYPESAFE_API_KEY" => " env-key " })
      expect(client.base_url).to eq("https://api.typesafe.ai")
    end

    it "applies explicit options over the environment" do
      client = described_class.new(
        api_key: "k", base_url: "https://example.org/", default_model: "m",
        timeout: 5, env: { "TYPESAFE_API_KEY" => "env" }
      )
      expect(client.base_url).to eq("https://example.org")
      expect(client.default_model).to eq("m")
      expect(client.timeout).to eq(5)
    end

    it "rejects invalid timeouts" do
      expect { described_class.new(api_key: "k", timeout: 0) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /must be a positive number/)
    end

    it "rejects invalid retry overrides" do
      expect { described_class.new(api_key: "k", retry_policy: { max_retries: -1 }) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /non-negative integer/)
      expect { described_class.new(api_key: "k", retry_policy: { backoff_jitter: 2 }) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /between 0 and 1/)
    end

    it "rejects invalid log levels" do
      expect { described_class.new(api_key: "k", log_level: :loud) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /Invalid log level/)
    end

    it "does not leak the API key through inspect" do
      expect(client.inspect).not_to include("test-key")
    end
  end

  describe "#system_one" do
    let(:questions) do
      {
        billing: Typesafe::SDK.noul("Is this billing?"),
        tone: Typesafe::SDK.choice("Tone?", { calm: nil, angry: nil }),
        urgency: Typesafe::SDK.score("Urgent?", %w[low high])
      }
    end

    it "posts to /v1/systemone with the resolved model" do
      expect(http).to receive(:request).with(
        method: :post,
        url: "https://api.typesafe.ai/v1/systemone",
        body: anything,
        headers: hash_including(
          "authorization" => "Bearer test-key",
          "content-type" => "application/json",
          "user-agent" => "typesafe-sdk-ruby/#{Typesafe::SDK::VERSION}"
        ),
        timeout: 10,
        signal: nil
      ).and_return(response(200, {
                              "model" => "jev-latest",
                              "answers" => { "billing" => { "type" => "noul", "noul" => 0.9 } },
                              "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
                            }))

      result = client.system_one(state: "text", questions: questions)
      expect(result.model).to eq("jev-latest")
      expect(result[:billing]).to be_a(Typesafe::SDK::NoulResponse)
      expect(result[:billing].noul).to eq(0.9)
      expect(result.usage.input_tokens).to eq(10)
    end

    it "sends JSON bodies with symbol-keyed questions" do
      captured = nil
      allow(http).to receive(:request) { |**kwargs|
        captured = kwargs; response(200, {
                                      "model" => "jev-latest", "answers" => {}, "usage" => {}
                                    })
      }
      client.system_one(state: { doc: "x" }, questions: { q: Typesafe::SDK.noul("q?") })
      body = JSON.parse(captured[:body])
      expect(body).to eq({
                           "state" => { "doc" => "x" },
                           "questions" => { "q" => { "type" => "noul", "instructions" => "q?", "criteria" => nil } },
                           "model" => "jev-latest"
                         })
    end

    it "raises on empty questions" do
      expect { client.system_one(state: "x", questions: {}) }
        .to raise_error(Typesafe::SDK::TypeSafeError, "At least one question is required.")
    end

    it "raises on invalid score criteria" do
      questions = { bad: { type: "score", instructions: nil, criteria: ["one"] } }
      expect { client.system_one(state: "x", questions: questions) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /at least two scores/)
    end

    it "raises APIError subclasses for error statuses" do
      allow(http).to receive(:request).and_return(
        response(401, { "error" => "bad key" }, "x-typesafe-request-id" => "req-1")
      )
      expect { client.system_one(state: "x", questions: { q: Typesafe::SDK.noul("q?") }) }
        .to raise_error(Typesafe::SDK::AuthenticationError, /401 bad key/) do |e|
        expect(e.request_id).to eq("req-1")
      end
    end
  end

  describe "retries" do
    it "retries retryable statuses and succeeds" do
      allow(http).to receive(:request)
        .and_return(response(500, { "error" => "boom" }), response(200, {
                                                                     "model" => "m", "answers" => { "q" => {
                                                                       "type" => "noul", "noul" => 0.5
                                                                     } }, "usage" => {}
                                                                   }))
      allow(client.logger).to receive(:info)

      result = client.system_one(
        state: "x",
        questions: { q: Typesafe::SDK.noul("q?") },
        retry_policy: { backoff_initial_ms: 1 }
      )
      expect(result[:q].noul).to eq(0.5)
      expect(http).to have_received(:request).twice
    end

    it "exhausts retries and raises the last error" do
      allow(http).to receive(:request).and_return(response(500, { "error" => "boom" }))
      allow(client.logger).to receive(:info)

      expect do
        client.system_one(
          state: "x",
          questions: { q: Typesafe::SDK.noul("q?") },
          retry_policy: { max_retries: 1, backoff_initial_ms: 1 }
        )
      end.to raise_error(Typesafe::SDK::InternalServerError, /500 boom/)
      expect(http).to have_received(:request).twice
    end

    it "does not retry non-retryable statuses" do
      allow(http).to receive(:request).and_return(response(404, { "error" => "nope" }))

      expect { client.system_one(state: "x", questions: { q: Typesafe::SDK.noul("q?") }) }
        .to raise_error(Typesafe::SDK::NotFoundError)
      expect(http).to have_received(:request).once
    end

    it "retries connection errors" do
      calls = 0
      allow(http).to receive(:request) do
        calls += 1
        raise Typesafe::SDK::APIConnectionError, "down" if calls == 1

        response(200, {
                   "model" => "m", "answers" => {}, "usage" => {}
                 })
      end
      allow(client.logger).to receive(:info)

      client.system_one(
        state: "x",
        questions: { q: Typesafe::SDK.noul("q?") },
        retry_policy: { backoff_initial_ms: 1 }
      )
      expect(http).to have_received(:request).twice
    end

    it "respects the api_connection_error policy flag" do
      allow(http).to receive(:request)
        .and_raise(Typesafe::SDK::APIConnectionError.new("down"))

      expect do
        client.system_one(
          state: "x",
          questions: { q: Typesafe::SDK.noul("q?") },
          retry_policy: { api_connection_error: false }
        )
      end.to raise_error(Typesafe::SDK::APIConnectionError)
      expect(http).to have_received(:request).once
    end
  end

  describe "header merging" do
    it "lets per-call headers override defaults but not auth" do
      allow(http).to receive(:request).and_return(response(200, {
                                                             "model" => "m", "answers" => {}, "usage" => {}
                                                           }))
      client.system_one(
        state: "x",
        questions: { q: Typesafe::SDK.noul("q?") },
        headers: { "X-Custom" => "1", "Authorization" => "hijack" }
      )
      expect(http).to have_received(:request).with(
        hash_including(headers: hash_including(
          "x-custom" => "1", "authorization" => "Bearer test-key"
        ))
      )
    end
  end
end
