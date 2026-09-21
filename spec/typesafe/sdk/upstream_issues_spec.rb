# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Upstream issue regressions" do
  let(:http) { instance_double(Typesafe::SDK::HTTP) }
  let(:client) { Typesafe::SDK::Client.new(api_key: "synthetic", http: http) }
  let(:success) do
    Typesafe::SDK::Response.new(status: 200, headers: Typesafe::SDK::Headers.new({}),
                                body: { "model" => "fixture", "answers" => {}, "usage" => {}, "models" => [] },
                                request_id: "fixture-id")
  end

  describe "#14 API key configuration" do
    ["", " \t\r\n", "example\nkey", "example\rkey", "example\tkey", "example\0key", "example\0", "example key",
     "exämple", "\xFF".b.force_encoding("UTF-8"), 123].each do |key|
      it "rejects invalid explicit keys without disclosing them: #{key.inspect}" do
        expect(http).not_to receive(:request)
        expect { Typesafe::SDK::Client.new(api_key: key, http: http, env: {}) }
          .to raise_error(Typesafe::SDK::TypeSafeError) do |error|
          expect(error.message).not_to include("example")
          expect(error.cause).to be_nil
        end
      end
    end

    ["example\nkey", "example\0"].each do |value|
      it "rejects control characters from the environment: #{value.inspect}" do
        expect { Typesafe::SDK::Client.new(env: { "TYPESAFE_API_KEY" => value }) }
          .to raise_error(Typesafe::SDK::TypeSafeError)
      end
    end

    it "does not wrap or retry header construction failures as connection errors" do
      transport = Typesafe::SDK::HTTP.new
      expect(transport).to receive(:request).once.and_call_original
      expect(transport).not_to receive(:perform)
      configured = Typesafe::SDK::Client.new(api_key: "synthetic", http: transport,
                                             default_headers: { "X-Example" => "bad\nvalue" })
      expect { configured.models.list }.to raise_error(ArgumentError)
    end

    it "trims and copies an explicit key before constructing authorization" do
      key = " synthetic \n".dup
      configured = Typesafe::SDK::Client.new(api_key: key, http: http)
      key.replace("changed")
      expect(http).to receive(:request).with(hash_including(headers: hash_including(
        "authorization" => "Bearer synthetic"
      ))).and_return(success)
      configured.models.list
    end
  end

  describe "#6 and #12 invalid API inputs" do
    [nil, 42, false].each do |state|
      it "rejects #{state.inspect} state before network I/O" do
        expect(http).not_to receive(:request)
        expect { client.system_one(state: state, questions: { q: Typesafe::SDK.noul("Question?") }) }
          .to raise_error(Typesafe::SDK::TypeSafeError, /state/)
      end
    end

    ["", {}, []].each do |state|
      it "preserves allowed empty #{state.class} state" do
        expect(http).to receive(:request).and_return(success)
        client.system_one(state: state, questions: { q: Typesafe::SDK.noul("Question?") })
      end
    end

    [nil, {}, { true: nil, false: nil }].each do |criteria|
      it "rejects a noul with no instructions or usable criteria: #{criteria.inspect}" do
        expect { Typesafe::SDK.noul(criteria: criteria) }
          .to raise_error(Typesafe::SDK::TypeSafeError, /instructions or criteria/)
      end
    end

    it "accepts a criteria-only noul" do
      expect { Typesafe::SDK.noul(criteria: { true: "A greeting" }) }.not_to raise_error
    end

    [[], ["one"], Array.new(11, "level"), ["low", nil, "high"]].each do |criteria|
      it "rejects invalid score criteria without renumbering: #{criteria.inspect}" do
        original = Marshal.dump(criteria)
        expect { Typesafe::SDK.score("Question?", criteria) }.to raise_error(Typesafe::SDK::TypeSafeError)
        expect(Marshal.dump(criteria)).to eq(original)
      end
    end

    [{}, (1..256).to_h { |n| [n, nil] }].each do |criteria|
      it "rejects #{criteria.length} choice options" do
        expect { Typesafe::SDK.choice("Question?", criteria) }.to raise_error(Typesafe::SDK::TypeSafeError)
      end
    end

    it "accepts boundary counts and preserves an empty-string score level" do
      expect(Typesafe::SDK.score("Question?", Array.new(10, ""))[:criteria].length).to eq(10)
      [1, 255].each do |count|
        expect(Typesafe::SDK.choice("Question?", (1..count).to_h { |n| [n, nil] })[:criteria].length).to eq(count)
      end
      expect(Typesafe::SDK.score("Question?", ["low", "", "high"])[:criteria]).to eq(["low", "", "high"])
    end

    [
      { "" => { type: "noul", instructions: "Question?" } },
      { q: { type: "noul", instructions: nil, criteria: {} } },
      { q: { type: "score", criteria: ["low", nil, "high"] } },
      { q: { type: "score", criteria: Array.new(11, "level") } },
      { q: { type: "choice", criteria: {} } }
    ].each_with_index do |questions, index|
      it "validates raw symbol and JSON question hashes (case #{index})" do
        expect(http).not_to receive(:request)
        [questions, JSON.parse(JSON.generate(questions))].each do |input|
          expect { client.system_one(state: "state", questions: input) }.to raise_error(Typesafe::SDK::TypeSafeError)
        end
      end
    end

    it "allows a whitespace-only question ID" do
      expect(http).to receive(:request).and_return(success)
      client.system_one(state: "state", questions: { "   " => Typesafe::SDK.noul("Question?") })
    end
  end

  describe "#9 server retry delays" do
    [{}, { "retry-after" => "" }, { "retry-after" => " \t " },
     { "retry-after-ms" => "" }, { "retry-after-ms" => " " },
     { "retry-after" => "garbage" }].each do |headers|
      it "uses configured backoff for #{headers.inspect}" do
        failure = Typesafe::SDK::Response.new(status: 503, headers: Typesafe::SDK::Headers.new(headers),
                                              body: {}, request_id: nil)
        allow(http).to receive(:request).and_return(failure, success)
        configured = Typesafe::SDK::Client.new(api_key: "test", http: http,
                                               retry_policy: { backoff_initial_ms: 200, backoff_jitter: 0 })
        expect(configured).to receive(:sleep_with_signal).with(200, nil)
        configured.models.list
      end
    end

    it "preserves explicit zero and falls back from blank milliseconds to valid seconds" do
      { "retry-after" => "0", "retry-after-ms" => "0" }.each do |name, value|
        expect(Typesafe::SDK::Retry.parse_retry_after(Typesafe::SDK::Headers.new(name => value))).to eq(0)
      end
      headers = Typesafe::SDK::Headers.new("retry-after-ms" => " ", "retry-after" => "2")
      expect(Typesafe::SDK::Retry.parse_retry_after(headers)).to eq(2000)
    end
  end

  describe "#13 additional typed errors" do
    { 402 => "PaymentRequiredError", 409 => "ConflictError", 413 => "PayloadTooLargeError" }.each do |status, name|
      it "raises #{name}, preserves response metadata, and does not retry by default" do
        headers = Typesafe::SDK::Headers.new("x-typesafe-request-id" => "req-error")
        failure = Typesafe::SDK::Response.new(status: status, headers: headers,
                                              body: { "detail" => "failed" }, request_id: "req-error")
        allow(http).to receive(:request).and_return(failure)
        expect { client.models.list }.to raise_error(Typesafe::SDK::APIError) do |error|
          expect(error.class.name.split("::").last).to eq(name)
          expect(error.status).to eq(status)
          expect(error.request_id).to eq("req-error")
          expect(error.headers).to eq(headers)
          expect(error.body).to eq("detail" => "failed")
        end
        expect(http).to have_received(:request).once
      end
    end
  end

  it "#4 sends numeric choice labels as strings and reads string-labeled answers" do
    expect(http).to receive(:request) do |**request|
      expect(JSON.parse(request[:body]).dig("questions", "q", "criteria")).to eq("0" => nil, "1" => nil)
      Typesafe::SDK::Response.new(status: 200, headers: Typesafe::SDK::Headers.new({}), request_id: nil,
                                  body: { "answers" => { "q" => { "type" => "choice", "choice" => "0",
                                                                  "probabilities" => { "0" => 0.9, "1" => 0.1 } } } })
    end
    result = client.system_one(state: "state", questions: { q: Typesafe::SDK.choice("Question?", 0 => nil, 1 => nil) })
    expect(result[:q].choice).to eq("0")
    expect(result[:q].probabilities["0"]).to eq(0.9)
  end
end
