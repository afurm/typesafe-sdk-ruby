# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/recording_http"

RSpec.describe "JS 0.7.0 changes and new upstream issues" do
  let(:http) { RecordingHTTP.new }
  let(:client) { Typesafe::SDK::Client.new(api_key: "k", http: http, compression: false) }

  describe "box questions" do
    it "defaults instructions to nil" do
      expect(Typesafe::SDK.box("The dog")).to eq(type: "box", instructions: "The dog")
      expect(Typesafe::SDK.box).to eq(type: "box", instructions: nil)
    end

    it "parses box answers with nil confidence and keeps unmodeled fields" do
      wire = { "type" => "box", "box" => { "top" => 0.1, "bottom" => 0.6, "left" => 0.25, "right" => 0.75 },
               "confidence" => nil, "extra" => { "k" => [1] } }
      result = Typesafe::SDK::SystemOneResult.new("model" => "m", "answers" => { "dog" => wire },
                                                  "usage" => { "input_tokens" => nil, "output_tokens" => nil })
      answer = result[:dog]
      expect(answer).to be_a(Typesafe::SDK::BoxResponse)
      expect([answer.box.top, answer.box.bottom, answer.box.left, answer.box.right]).to eq([0.1, 0.6, 0.25, 0.75])
      expect(answer.box.to_h).to eq(wire["box"])
      expect(answer.confidence).to be_nil
      expect(answer.to_h).to eq(wire)
      expect([result.usage.input_tokens, result.usage.output_tokens]).to eq([nil, nil])
    end

    it "sends structured box instructions without local validation" do
      client.system_one(state: "s", questions: { dog: Typesafe::SDK.box({ find: "the dog" }) })
      expect(http.requests.first.body.dig("questions", "dog")).to eq("type" => "box",
                                                                     "instructions" => { "find" => "the dog" })
    end
  end

  describe "request validation added in JS 0.7.0" do
    ["spam", ["spam"], 1].each do |criteria|
      it "rejects non-object noul criteria #{criteria.inspect}" do
        expect do
          client.system_one(state: "s", questions: { spam: { type: "noul", instructions: "Spam?", criteria: } })
        end
          .to raise_error(Typesafe::SDK::TypeSafeError, "Noul question :spam criteria must be an object.")
        expect { Typesafe::SDK.noul("Spam?", criteria: criteria) }
          .to raise_error(Typesafe::SDK::TypeSafeError, /criteria must be an object/)
      end
    end

    it "accepts images and text with images as state" do
      photo = Typesafe::SDK.image("\xFF\xD8\xFF".b)
      [photo, Typesafe::SDK.with_assets("See ", photo)].each do |state|
        client.system_one(state: state, questions: { q: Typesafe::SDK.noul("?") })
      end
      expect(http.requests.map { |request| request.body["state"] }).to eq([photo.to_s, "See #{photo}"])
    end
  end

  describe "#17 non-finite numbers" do
    it "sends NaN and infinities as strings, as JS 0.7.0 does, in state and extra fields" do
      client.system_one(state: { value: Float::NAN, values: [1, Float::INFINITY, -Float::INFINITY, 1.5] },
                        questions: { q: Typesafe::SDK.noul("x") }, extra_body: { limit: Float::INFINITY })
      body = http.requests.first.body
      expect(body["state"]).to eq("value" => "NaN", "values" => [1, "Infinity", "-Infinity", 1.5])
      expect(body["limit"]).to eq("Infinity")
    end
  end

  describe "#18 redacting credential headers" do
    {
      ["x-api-key", "sk-live-ABCDEFGH x"] => "***GH x",
      ["x-api-key", "Bearer sk-live-ABCDEFGH"] => "***EFGH",
      ["proxy-authorization", "TOKEN "] => "***",
      ["authorization", "sk-live-ABCDEFGH x"] => "***GH x",
      ["authorization", "Bearer sk-1234567890abcdef"] => "Bearer ***cdef",
      ["authorization", "Basic   c2VjcmV0"] => "Basic ***",
      %w[Authorization Bearer] => "***",
      %w[authorization sk-live-ABCDEFGH] => "***EFGH"
    }.each do |(name, value), expected|
      it "masks #{name}: #{value.inspect} as #{expected.inspect}" do
        redacted = Typesafe::SDK::Redaction.redact_headers(name => value)[name]
        expect(redacted).to eq(expected)
        secret = value.split.find { |word| word.length > 6 && word != "Bearer" }
        expect(redacted).not_to include(secret) if secret
      end
    end
  end

  describe "#15 Cloudflare HTML error pages" do
    let(:html) { "<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title></head></html>" }

    it "explains an edge block and keeps the error class, body, and headers" do
      headers = Typesafe::SDK::Headers.new("content-type" => "text/html", "cf-ray" => "8f1a2b3c4d5e6f70-IAD",
                                           "server" => "cloudflare")
      error = Typesafe::SDK::APIError.from_response(403, html, headers)
      expect(error).to be_a(Typesafe::SDK::PermissionDeniedError)
      expect(error.message).to start_with("403 The response is a Cloudflare HTML page, not a TypeSafe API error " \
                                          "(cf-ray 8f1a2b3c4d5e6f70-IAD).")
      expect(error.message).not_to include("<html")
      expect(error.body).to eq(html)
    end

    it "recognizes a Cloudflare server header without a ray ID" do
      error = Typesafe::SDK::APIError.from_response(503, html, Typesafe::SDK::Headers.new("server" => "cloudflare"))
      expect(error.message).to start_with("503 The response is a Cloudflare HTML page, not a TypeSafe API error.")
    end

    it "keeps other HTML and API errors unchanged" do
      plain = Typesafe::SDK::APIError.from_response(403, html, Typesafe::SDK::Headers.new({}))
      expect(plain.message).to eq("403 #{html}")
      json = Typesafe::SDK::APIError.from_response(403, { "error" => "denied" },
                                                   Typesafe::SDK::Headers.new("cf-ray" => "x"))
      expect(json.message).to eq("403 denied")
    end
  end
end
