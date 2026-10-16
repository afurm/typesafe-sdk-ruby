# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/recording_http"

RSpec.describe "Request compression" do
  let(:http) { RecordingHTTP.new { |request| request.http_method == :get ? { "models" => [] } : {} } }
  let(:large) { "x" * Typesafe::SDK::Compression::MIN_COMPRESSED_BODY_BYTES }

  def send_both(state: large, headers: {}, **config)
    client = Typesafe::SDK::Client.new(api_key: "k", http: http, **config)
    client.system_one(state: state, questions: { q: Typesafe::SDK.noul("?") }, headers: headers)
    client.models.list
    client
  end

  context "with zstd-ruby installed" do
    before { skip "zstd-ruby is not installed" unless Typesafe::SDK::Compression.available? }

    [nil, :zstd, "zstd"].each do |option|
      it "compression #{option.inspect} sends bodies of 1 KiB or more with zstd" do
        client = send_both(compression: option)
        post, get = http.requests
        expect(client.compression).to eq(:zstd)
        expect(post.content_encoding).to eq("zstd")
        expect(post.raw.bytesize).to be < large.bytesize
        expect(post.body["state"]).to eq(large)
        expect(get.headers).not_to have_key("content-encoding")
      end
    end

    it "sends bodies under 1 KiB uncompressed" do
      send_both(state: "x")
      expect(http.requests.first.content_encoding).to be_nil
      expect(http.requests.first.raw).to eq(JSON.generate(http.requests.first.body))
    end

    it "measures the body in UTF-8 bytes" do
      send_both(state: "é" * (Typesafe::SDK::Compression::MIN_COMPRESSED_BODY_BYTES / 2))
      expect(http.requests.first.content_encoding).to eq("zstd")
    end

    it "replaces a caller's Content-Encoding with the one the body is compressed with" do
      send_both(headers: { "Content-Encoding" => "br" })
      expect(http.requests.first.content_encoding).to eq("zstd")
    end

    it "compresses multipart bodies" do
      send_both(state: Typesafe::SDK.image("\x89PNG\r\n\x1A\n".b + ("\0" * large.bytesize)))
      request = http.requests.first
      expect(request.content_encoding).to eq("zstd")
      expect(request.headers["content-type"]).to match(%r{\Amultipart/form-data; boundary=\h{32}\z})
      expect(request.parts.map { |part| part["name"] }).to eq(["asset-0"])
    end
  end

  it "compression false sends bodies uncompressed and drops a caller's Content-Encoding" do
    client = send_both(compression: false, headers: { "content-encoding" => "br" })
    expect(client.compression).to be(false)
    expect(http.requests.first.content_encoding).to be_nil
    expect(http.requests.first.raw).to be_a(String)
    expect(http.requests.first.body["state"]).to eq(large)
  end

  it "sends bodies uncompressed without zstd-ruby and rejects an explicit zstd" do
    allow(Typesafe::SDK::Compression).to receive(:available?).and_return(false)
    client = send_both
    expect(client.compression).to be(false)
    expect(http.requests.first.content_encoding).to be_nil
    expect { Typesafe::SDK::Client.new(api_key: "k", compression: :zstd) }
      .to raise_error(Typesafe::SDK::TypeSafeError, /requires the zstd-ruby gem.*`compression: false`/)
  end

  ["gzip", :br, true].each do |option|
    it "rejects compression #{option.inspect}" do
      expect { Typesafe::SDK::Client.new(api_key: "k", compression: option) }
        .to raise_error(Typesafe::SDK::TypeSafeError, "`compression` must be :zstd or false, got #{option.inspect}.")
    end
  end
end
