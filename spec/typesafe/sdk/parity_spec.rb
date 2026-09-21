# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Official JS 0.6.0 parity" do
  fixture = JSON.parse(File.read(File.expand_path("../../fixtures/js-0.6.0.json", __dir__)))

  it "tracks the recorded upstream release" do
    expect(Typesafe::SDK::UPSTREAM_VERSION).to eq(fixture.dig("upstream", "version"))
  end

  it "serializes all three question types identically" do
    questions = {
      yes: Typesafe::SDK.noul("Is it urgent?", criteria: { true: "urgent", false: "routine" }),
      category: Typesafe::SDK.choice(nil, billing: nil, other: { description: "other" }),
      rating: Typesafe::SDK.score("Priority?", [nil, "medium", ["high"]])
    }
    expect(JSON.parse(JSON.generate(questions))).to eq(fixture["questions"])
  end

  it "forwards extension fields and exposes successful response metadata" do
    adapter = instance_double(Typesafe::SDK::HTTP)
    headers = Typesafe::SDK::Headers.new("x-typesafe-request-id" => "req-parity")
    response = Typesafe::SDK::Response.new(status: 200, headers: headers, request_id: "req-parity",
                                           body: { "model" => "jev-latest", "answers" => {}, "usage" => {} })
    expect(adapter).to receive(:request) do |**request|
      expect(request[:url]).to eq(fixture.dig("request", "url"))
      expect(request[:method].to_s.upcase).to eq(fixture.dig("request", "method"))
      expect(JSON.parse(request[:body])).to eq(fixture.dig("request", "body"))
      response
    end
    client = Typesafe::SDK::Client.new(api_key: "test", http: adapter)
    result = client.system_one(state: { document: "example" }, questions: fixture["questions"],
                               extra_body: { future_option: nil, nested: { enabled: true } }, with_response: true)
    expect(result.data).to be_a(Typesafe::SDK::SystemOneResult)
    expect(result.response.status).to eq(fixture.dig("response_metadata", "status"))
    expect(result.request_id).to eq(fixture.dig("response_metadata", "request_id"))
  end

  it "preserves every answer field, fractional scores, string rubric keys, and usage" do
    wire = fixture.fetch("result")
    result = Typesafe::SDK::SystemOneResult.new(wire)
    expect(result.model).to eq(wire["model"])
    expect(result.usage.input_tokens).to eq(wire.dig("usage", "input_tokens"))
    expect(result.usage.output_tokens).to eq(wire.dig("usage", "output_tokens"))
    wire.fetch("answers").each do |name, fields|
      answer = result[name]
      expect(result[name.to_sym]).to equal(answer)
      fields.each { |field, value| expect(answer.public_send(field)).to eq(value) }
    end
  end

  fixture.fetch("retry_flags").each do |example|
    it "matches the #{example['field']} default for #{example['value'].inspect}" do
      field = example.fetch("field").to_sym
      client = Typesafe::SDK::Client.new(api_key: "test", retry_policy: { field => example["value"] })
      expect(client.retry[field]).to eq(example["resolved"])
    end
  end

  fixture["errors"].each_with_index do |example, index|
    it "matches error class, message, and metadata for fixture #{index}" do
      headers = Typesafe::SDK::Headers.new("x-typesafe-request-id" => "req-error", "retry-after-ms" => "12.5")
      error = Typesafe::SDK::APIError.from_response(example["status"], example["body"], headers)
      expect(error.class.name.split("::").last).to eq(example["name"])
      expect(error.message).to eq(example["message"])
      expect(error.request_id).to eq(example["request_id"])
      expect(error.retry_after_ms).to eq(example["retry_after_ms"]) if example.key?("retry_after_ms")
    end
  end

  fixture["retry_headers"].each do |example|
    it "matches upstream Retry-After parsing for #{example['headers']}" do
      headers = Typesafe::SDK::Headers.new(example["headers"])
      expect(Typesafe::SDK::Retry.parse_retry_after(headers)).to eq(example["milliseconds"])
    end
  end
end
