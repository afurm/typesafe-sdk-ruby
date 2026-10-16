# frozen_string_literal: true

# An HTTP adapter that records each request as sent, decoding zstd and multipart bodies.
class RecordingHTTP
  Recorded = Struct.new(:http_method, :url, :headers, :raw, :body, :parts, keyword_init: true) do
    def content_type
      headers["content-type"]&.split(";")&.first
    end

    def content_encoding
      headers["content-encoding"]
    end
  end

  attr_reader :requests

  def initialize(body = { "model" => "m", "answers" => {}, "usage" => {} }, &responder)
    @requests = []
    @responder = responder || ->(_request) { body }
  end

  def request(method:, url:, headers:, body:, timeout:, signal:)
    _ = [timeout, signal]
    recorded = decode(method, url, headers, body)
    @requests << recorded
    Typesafe::SDK::Response.new(status: 200, headers: Typesafe::SDK::Headers.new({}),
                                body: @responder.call(recorded), request_id: nil)
  end

  def self.decompress(headers, body)
    return body unless headers["content-encoding"] == "zstd"

    require "zstd-ruby"
    Zstd.decompress(body)
  end

  # Split a `multipart/form-data` body into parts with their headers and content.
  def self.multipart_parts(content_type, raw)
    boundary = content_type[/boundary=(\h+)\z/, 1] or raise "No boundary in #{content_type}"
    raise "Missing closing boundary" unless raw.end_with?("\r\n--#{boundary}--\r\n")

    raw.b.split("--#{boundary}").drop(1)[0...-1].map do |chunk|
      head, content = chunk.delete_prefix("\r\n").split("\r\n\r\n", 2)
      fields = head.split("\r\n").to_h { |line| line.split(": ", 2).then { |k, v| [k.downcase, v] } }
      disposition = fields.fetch("content-disposition")
      { "name" => disposition[/ name="([^"]*)"/, 1], "filename" => disposition[/ filename="([^"]*)"/, 1],
        "content_type" => fields.fetch("content-type"), "content" => content.delete_suffix("\r\n") }
    end
  end

  private

  def decode(method, url, headers, body)
    raw = body && self.class.decompress(headers, body)
    parts = nil
    json = raw
    if headers["content-type"].to_s.start_with?("multipart/form-data")
      parts = self.class.multipart_parts(headers["content-type"], raw)
      json = parts.shift.fetch("content")
    end
    Recorded.new(http_method: method, url: url, headers: headers, raw: body, body: json && JSON.parse(json),
                 parts: parts)
  end
end
