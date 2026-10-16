# frozen_string_literal: true

require "spec_helper"
require "pathname"
require "stringio"
require "tempfile"
require_relative "../../support/recording_http"

RSpec.describe "Image assets" do
  png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        .unpack1("m")

  let(:http) { RecordingHTTP.new }
  let(:client) { Typesafe::SDK::Client.new(api_key: "k", http: http, compression: false) }
  let(:noul) { Typesafe::SDK.noul("?") }

  def sent_assets(request)
    request.body.fetch("assets").transform_values do |entry|
      part = request.parts.find { |candidate| candidate["name"] == entry["part"] }
      entry.merge("content" => part["content"], "content_type" => part["content_type"])
    end
  end

  describe Typesafe::SDK::Image do
    it "copies and freezes string bytes and has a unique reference" do
      bytes = png.dup
      photo = Typesafe::SDK.image(bytes)
      bytes.replace("changed")
      expect(photo.data).to eq(png)
      expect(photo.data).to be_frozen
      expect(photo.to_s).to match(/\A<image:\h{32}>\z/)
      expect(photo.to_s).not_to eq(Typesafe::SDK.image(png).to_s)
      expect(photo.inspect).to include(photo.to_s)
      expect(photo.inspect).not_to include("PNG")
      expect(JSON.generate([photo])).to eq(%(["#{photo}"]))
    end

    it "reads an IO now and a Pathname when the request is sent" do
      expect(Typesafe::SDK.image(StringIO.new(png)).data).to eq(png)
      Tempfile.create(["photo", ".png"]) do |file|
        file.binmode
        file.write(png)
        file.flush
        photo = Typesafe::SDK.image(Pathname(file.path))
        File.binwrite(file.path, "\xFF\xD8\xFFlater".b)
        client.system_one(state: photo, questions: { q: noul })
        expect(sent_assets(http.requests.first).values.first)
          .to include("content" => "\xFF\xD8\xFFlater".b, "content_type" => "image/jpeg")
      end
    end

    it "rejects empty, missing, and unsupported data" do
      expect { Typesafe::SDK.image("") }.to raise_error(Typesafe::SDK::TypeSafeError, "Image data is empty.")
      expect { Typesafe::SDK.image(StringIO.new) }.to raise_error(Typesafe::SDK::TypeSafeError, "Image data is empty.")
      expect { Typesafe::SDK.image(Pathname("/nonexistent/photo.png")) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /Image file could not be read/)
      [nil, 42, [1, 2]].each do |data|
        expect { Typesafe::SDK.image(data) }
          .to raise_error(Typesafe::SDK::TypeSafeError, /Image data must be file bytes .*; got #{data.class}/)
      end
    end

    it "names the asset when a Pathname can't be read at send time" do
      Tempfile.create(["photo", ".png"]) do |file|
        file.write(png)
        file.flush
        photo = Typesafe::SDK.image(Pathname(file.path))
        File.delete(file.path)
        expect { client.system_one(state: "<a>", questions: { q: noul }, assets: { "<a>" => photo }) }
          .to raise_error(Typesafe::SDK::TypeSafeError, /Asset "<a>" could not be read/)
      end
      expect(http.requests).to be_empty
    end

    it "detects PNG and JPEG and sends other bytes as application/octet-stream" do
      expect(described_class.content_type_of(png)).to eq("image/png")
      expect(described_class.content_type_of("\xFF\xD8\xFF".b)).to eq("image/jpeg")
      expect(described_class.content_type_of("GIF89a")).to eq("application/octet-stream")
    end
  end

  it "sends images in state and question content under their references" do
    photo = Typesafe::SDK.image(png)
    listing = Typesafe::SDK.image("\xFF\xD8\xFF".b)
    client.system_one(state: { photo: photo }, questions: { q: Typesafe::SDK.noul(["Same as listing?", listing]) })
    request = http.requests.first
    expect(request.content_type).to eq("multipart/form-data")
    expect(request.body["state"]).to eq("photo" => photo.to_s)
    expect(request.body.dig("questions", "q", "instructions")).to eq(["Same as listing?", listing.to_s])
    expect(request.body["assets"]).to eq(photo.to_s => { "type" => "image", "part" => "asset-0" },
                                         listing.to_s => { "type" => "image", "part" => "asset-1" })
    expect(request.parts.map { |part| [part["filename"], part["content"]] })
      .to eq([["asset-0", png], ["asset-1", "\xFF\xD8\xFF".b]])
  end

  it "accepts an image as the whole state and in box instructions" do
    photo = Typesafe::SDK.image(png)
    client.system_one(state: photo, questions: { where: Typesafe::SDK.box(Typesafe::SDK.with_assets("Find ", photo)) },
                      model: "jev-preview")
    body = http.requests.first.body
    expect(body).to include("state" => photo.to_s, "model" => "jev-preview")
    expect(body.dig("questions", "where")).to eq("type" => "box", "instructions" => "Find #{photo}")
    expect(body["assets"].keys).to eq([photo.to_s])
  end

  it "writes an image as its name when it is also in assets, and sends each image once per reference" do
    photo = Typesafe::SDK.image(png)
    client.system_one(state: Typesafe::SDK.with_assets("Compare ", photo, " with <photo>"),
                      questions: { q: Typesafe::SDK.noul([photo]) }, assets: { "<photo>": photo })
    body = http.requests.first.body
    expect(body["state"]).to eq("Compare <photo> with <photo>")
    expect(body.dig("questions", "q", "instructions")).to eq(["<photo>"])
    expect(body["assets"].keys).to eq(["<photo>"])

    client.system_one(state: "Compare <photo> with #{photo}", questions: { q: noul }, assets: { "<photo>" => photo })
    expect(http.requests.last.body["assets"].keys).to eq(["<photo>", photo.to_s])
  end

  it "attaches to text only the images whose references it contains" do
    photo = Typesafe::SDK.image(png)
    listing = Typesafe::SDK.image(png)
    cycle = { photo: photo }
    cycle[:self] = cycle
    expect(Typesafe::SDK.with_assets("no images ", 1, nil).assets).to eq([])
    # A Hash is written with `to_s`, which includes the image's reference, even through a cycle.
    expect(Typesafe::SDK.with_assets("x", cycle).assets).to eq([photo])
    expect(Typesafe::SDK.with_assets([photo, listing]).assets).to eq([photo, listing])
    expect(Typesafe::SDK.with_assets(Typesafe::SDK.with_assets(photo), "and").assets).to eq([photo])
    expect(Typesafe::SDK.with_assets("x", nil, 1).text).to eq("x1")
  end

  it "raises before sending for unattached references, unused names, bad assets, and cycles" do
    photo = Typesafe::SDK.image(png)
    state = { photo: photo }
    state[:self] = state
    {
      { state: "Inspect #{photo}" } => /Image references without an attached image: #{photo}\. .*with_assets/,
      { state: "x", assets: { "<a>" => photo } } => /Assets not referenced in the request: <a>\./,
      { state: "<a>", assets: { "<a>" => png } } => /Asset "<a>" must be an image/,
      { state: "x", assets: { "" => photo } } => /Asset names must be nonempty/,
      { state: "x", assets: [photo] } => /`assets` must be a Hash/,
      { state: state } => /circular reference/
    }.each do |request, message|
      expect { client.system_one(questions: { q: noul }, **request) }
        .to raise_error(Typesafe::SDK::TypeSafeError, message)
    end
    expect(http.requests).to be_empty
  end

  it "allows the same container more than once when it is not a cycle" do
    shared = { note: "x" }
    client.system_one(state: { a: shared, b: [shared, shared] }, questions: { q: noul })
    expect(http.requests.first.body["state"]).to eq("a" => { "note" => "x" }, "b" => [{ "note" => "x" }] * 2)
  end

  it "sends the request as it was when system_one was called" do
    state = { "note" => +"before" }
    adapter = RecordingHTTP.new do |_|
      state["note"] << " after"
      { "model" => "m", "answers" => {}, "usage" => {} }
    end
    Typesafe::SDK::Client.new(api_key: "k", http: adapter, compression: false)
                         .system_one(state: state, questions: { q: noul })
    expect(adapter.requests.first.body["state"]).to eq("note" => "before")
  end

  it "doesn't read Pathname data when request options are invalid" do
    photo = Typesafe::SDK.image(Pathname(__FILE__))
    expect(photo).not_to receive(:read)
    expect { client.system_one(state: photo, questions: { q: noul }, timeout: 0) }
      .to raise_error(Typesafe::SDK::TypeSafeError, /timeout/)
  end

  it "raises APIUserAbortError without reading or sending when already canceled" do
    photo = Typesafe::SDK.image(Pathname(__FILE__))
    signal = Typesafe::SDK::Signal.new
    signal.cancel
    expect(photo).not_to receive(:read)
    expect { client.system_one(state: photo, questions: { q: noul }, signal: signal) }
      .to raise_error(Typesafe::SDK::APIUserAbortError)
    expect(http.requests).to be_empty
  end

  it "raises APIUserAbortError when canceled while reading assets" do
    signal = Typesafe::SDK::Signal.new
    photo = Typesafe::SDK.image(Pathname(__FILE__))
    allow(photo).to receive(:read) do
      signal.cancel
      png
    end
    expect { client.system_one(state: photo, questions: { q: noul }, signal: signal) }
      .to raise_error(Typesafe::SDK::APIUserAbortError)
    expect(http.requests).to be_empty
  end

  it "logs the request payload at debug level without image bytes" do
    logger = Class.new do
      attr_reader :entries

      def initialize = @entries = []
      %i[debug info warn error].each { |m| define_method(m) { |message, **data| @entries << [m, message, data] } }
    end.new
    photo = Typesafe::SDK.image(png)
    Typesafe::SDK::Client.new(api_key: "k", http: http, compression: false, logger: logger, log_level: :debug)
                         .system_one(state: photo, questions: { q: noul })
    _, _, data = logger.entries.find { |_, message, _| message.include?("->") }
    expect(data[:body]["assets"]).to eq(photo.to_s => { "type" => "image", "part" => "asset-0" })
    expect(data[:body].to_s).not_to include("PNG")
    expect(data[:headers]["content-type"]).to start_with("multipart/form-data; boundary=")
  end
end
