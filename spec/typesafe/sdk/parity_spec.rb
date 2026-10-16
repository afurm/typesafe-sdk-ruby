# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/recording_http"

RSpec.describe "Official JS 0.7.0 parity" do
  fixture = JSON.parse(File.read(File.expand_path("../../fixtures/js-0.7.0.json", __dir__), encoding: "UTF-8"))
  png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
  jpeg = "/9j/AA=="

  # Ruby's noul builder writes omitted criteria as null; JavaScript omits the property.
  def without_null_criteria(body)
    body.merge("questions" => body["questions"].transform_values do |question|
      question["type"] == "noul" && question["criteria"].nil? ? question.except("criteria") : question
    end)
  end

  # Replace generated image references, which are random, with stable labels.
  def normalize(value, labels)
    json = JSON.generate(value)
    labels.each { |label, asset| json = json.gsub(asset.to_s, "<ref:#{label}>") }
    JSON.parse(json)
  end

  def parts_for_fixture(parts)
    parts.map do |part|
      part.except("content").merge("data_base64" => [part["content"]].pack("m0"))
    end
  end

  it "tracks the recorded upstream release" do
    expect(Typesafe::SDK::UPSTREAM_VERSION).to eq(fixture.dig("upstream", "version"))
  end

  it "serializes all four question types identically" do
    questions = {
      yes: Typesafe::SDK.noul("Is it urgent?", criteria: { true: "urgent", false: "routine" }),
      category: Typesafe::SDK.choice(nil, billing: nil, other: { description: "other" }),
      rating: Typesafe::SDK.score("Priority?", ["low", "medium", ["high"]]),
      where: Typesafe::SDK.box("The damaged area")
    }
    expect(JSON.parse(JSON.generate(questions))).to eq(fixture["questions"])
  end

  it "sends the same JSON body, with non-finite numbers as strings (upstream #17)" do
    http = RecordingHTTP.new
    client = Typesafe::SDK::Client.new(api_key: "test", http: http, compression: false)
    client.system_one(state: { document: "example", score: Float::NAN,
                               limits: [1, Float::INFINITY, -Float::INFINITY] },
                      questions: fixture["questions"], extra_body: { future_option: nil, nested: { enabled: true } })
    request = http.requests.first
    expected = fixture.fetch("request")
    expect(request.url).to eq(expected["url"])
    expect(request.http_method.to_s.upcase).to eq(expected["method"])
    expect(request.content_type).to eq(expected["content_type"])
    expect(request.content_encoding).to eq(expected["content_encoding"])
    expect(request.body).to eq(expected["body"])
  end

  context "with assets" do
    let(:http) { RecordingHTTP.new }
    let(:client) { Typesafe::SDK::Client.new(api_key: "test", http: http) }
    let(:photo) { Typesafe::SDK::Image.from_base64(png) }
    let(:listing) { Typesafe::SDK::Image.from_base64(jpeg) }
    let(:gif) { Typesafe::SDK.image("GIF89a") }

    before { skip "zstd-ruby is not installed" unless Typesafe::SDK::Compression.available? }

    it "sends the same multipart requests, parts, and compression" do
      client.system_one(state: "Inspect <a> and <b>", questions: { q: Typesafe::SDK.noul("Is <a> like <b>?") },
                        assets: { "<a>" => Typesafe::SDK::Image.from_base64(png),
                                  "<b>" => Typesafe::SDK::Image.from_base64(jpeg) })
      client.system_one(
        state: { photo: photo, caption: Typesafe::SDK.with_assets("Inspect ", photo, " beside ", listing),
                 other: gif },
        questions: {
          q1: Typesafe::SDK.noul([photo]),
          q2: Typesafe::SDK.score(Typesafe::SDK.with_assets("Rate ", listing, " (", 1, ")"), %w[bad good]),
          q3: Typesafe::SDK.noul(Typesafe::SDK.join_assets(["Is", photo, "clear?"], " ")),
          q4: Typesafe::SDK.box(listing)
        },
        assets: { "<photo>" => photo }
      )
      client.system_one(state: "Compare <photo> with #{photo}", questions: { q: Typesafe::SDK.noul("?") },
                        assets: { "<photo>" => photo })

      expected = fixture.fetch("asset_requests")
      expect(http.requests.length).to eq(expected.length)
      http.requests.zip(expected).each do |request, wire|
        expect(request.content_type).to eq(wire["content_type"])
        expect(request.content_encoding).to eq(wire["content_encoding"])
        sent = normalize({ "body" => without_null_criteria(request.body), "parts" => parts_for_fixture(request.parts) },
                         { "photo" => photo, "listing" => listing, "gif" => gif })
        expect(sent).to eq("body" => wire["body"], "parts" => wire["parts"])
      end
    end

    it "joins text and images like withAssets.join" do
      joined = Typesafe::SDK.join_assets([photo, "and", Typesafe::SDK.with_assets(listing), nil, 1], " ")
      texts = normalize({ "spaced" => joined.text, "spaced_assets" => joined.assets.map(&:to_s),
                          "default_separator" => Typesafe::SDK.join_assets([photo, listing]).text,
                          "empty" => Typesafe::SDK.join_assets([]).text }, { "photo" => photo, "listing" => listing })
      expect(texts).to eq(fixture["join_texts"])
    end

    it "raises the same asset validation errors before sending" do
      errors = fixture.fetch("asset_errors")
      attempt = lambda do |**request|
        client.system_one(questions: { q: Typesafe::SDK.noul("?") }, **request)
      rescue Typesafe::SDK::TypeSafeError => e
        normalize(e.message, { "photo" => photo })
      end
      expect(attempt.call(state: "Inspect <photo>",
                          assets: { "<photo>" => photo, "<unused>" => Typesafe::SDK::Image.from_base64(png),
                                    '<"quoted">' => photo })).to eq(errors["unreferenced"])
      expect(attempt.call(state: photo, assets: { "<first>" => photo, "<second>" => photo }))
        .to eq(errors["last_name_wins"])
      # Ruby names its own remedy: string interpolation instead of untagged template literals.
      expect(attempt.call(state: "Inspect #{photo}"))
        .to start_with(errors["missing_reference"].split(". ").first)
      expect(http.requests).to be_empty
      { "empty_image" => -> { Typesafe::SDK.image("") },
        "invalid_base64" => -> { Typesafe::SDK::Image.from_base64("not base64!") },
        "data_url" => -> { Typesafe::SDK::Image.from_base64("data:image/png;base64,#{png}") },
        "empty_base64" => -> { Typesafe::SDK::Image.from_base64("") } }.each do |name, call|
        expect(&call).to raise_error(Typesafe::SDK::TypeSafeError, errors[name])
      end
    end

    fixture.fetch("base64").each do |example|
      it "decodes base64 like atob for #{example['text'][0, 16].inspect}" do
        if example["error"]
          expect { Typesafe::SDK::Image.from_base64(example["text"]) }
            .to raise_error(Typesafe::SDK::TypeSafeError, example["error"])
        else
          expect(Typesafe::SDK::Image.from_base64(example["text"]).data.unpack1("H*")).to eq(example["hex"])
        end
      end
    end

    it "compresses bodies of 1 KiB or more, measured in UTF-8 bytes" do
      fixture.fetch("compression").each do |example|
        state = example["state_char"] * example["state_length"]
        client.system_one(state: state, questions: { q: Typesafe::SDK.noul("?") })
        request = http.requests.last
        expect(request.content_encoding).to eq(example["content_encoding"])
        expect(request.body["state"] == state).to eq(example["state_received"])
      end
    end
  end

  it "forwards extension fields and exposes successful response metadata" do
    adapter = instance_double(Typesafe::SDK::HTTP)
    headers = Typesafe::SDK::Headers.new("x-typesafe-request-id" => "req-parity")
    response = Typesafe::SDK::Response.new(status: 200, headers: headers, request_id: "req-parity",
                                           body: { "model" => "jev-latest", "answers" => {}, "usage" => {} })
    expect(adapter).to receive(:request) do |**request|
      expect(request[:url]).to eq(fixture.dig("request", "url"))
      expect(request[:method].to_s.upcase).to eq(fixture.dig("request", "method"))
      expected = fixture.dig("request", "body").merge("state" => { "document" => "example" })
      expect(JSON.parse(request[:body])).to eq(expected)
      response
    end
    client = Typesafe::SDK::Client.new(api_key: "test", http: adapter, compression: false)
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
      expect(answer.to_h).to eq(fields)
      fields.each do |field, value|
        actual = answer.public_send(field)
        expect(actual.respond_to?(:to_h) && value.is_a?(Hash) ? actual.to_h : actual).to eq(value)
      end
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
    it "matches baseline errors with the documented #13 correction for fixture #{index}" do
      headers = Typesafe::SDK::Headers.new("x-typesafe-request-id" => "req-error", "retry-after-ms" => "12.5")
      error = Typesafe::SDK::APIError.from_response(example["status"], example["body"], headers)
      # Ruby adds a ConflictError subclass for upstream #13, preserving APIError rescue.
      expected_class = example["status"] == 409 ? "ConflictError" : example["name"]
      expect(error.class.name.split("::").last).to eq(expected_class)
      expect(error.message).to eq(example["message"])
      expect(error.request_id).to eq(example["request_id"])
      expect(error.retry_after_ms).to eq(example["retry_after_ms"]) if example.key?("retry_after_ms")
    end
  end

  fixture["retry_headers"].each do |example|
    it "matches baseline Retry-After parsing with the documented #9 correction for #{example['headers']}" do
      headers = Typesafe::SDK::Headers.new(example["headers"])
      # Explicit correction for upstream #9: a blank ms header falls back to valid seconds.
      expected = example["headers"]["retry-after-ms"] == "" ? 9000 : example["milliseconds"]
      expect(Typesafe::SDK::Retry.parse_retry_after(headers)).to eq(expected)
    end
  end
end
