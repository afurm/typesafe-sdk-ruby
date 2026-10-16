# frozen_string_literal: true

require "json"
require "pathname"
require "securerandom"

module Typesafe
  module SDK
    # A PNG or JPEG image asset, created by {SDK.image} or {Image.from_base64}.
    #
    # Place it in `state`, question instructions, or criteria, join it into text with
    # {SDK.with_assets}, or pass it in `assets:` under a name of your choice.
    class Image
      # The file signatures that PNG (PNG spec §5.2) and JPEG (ITU T.81 SOI marker) files start
      # with, and the content type each identifies.
      CONTENT_TYPES = [
        ["image/png", "\x89PNG\r\n\x1A\n".b],
        ["image/jpeg", "\xFF\xD8\xFF".b]
      ].freeze

      # The asset type sent to the API.
      def type
        "image"
      end

      # The frozen binary file bytes, or a `Pathname` read when the request is sent.
      attr_reader :data

      # @param data [String, Pathname, #read] file bytes, a path to read when the request is
      #   sent, or an IO read now.
      # @raise [TypeSafeError] `data` is empty, unreadable, or not a supported type.
      def initialize(data)
        @data = coerce(data)
        size = @data.is_a?(Pathname) ? file_size(@data) : @data.bytesize
        raise TypeSafeError, "Image data is empty." if size.zero?

        @reference = "<image:#{SecureRandom.hex(16)}>".freeze
      end

      # Create an image from base64-encoded file bytes, decoding them now.
      #
      # @param text [String] the file bytes, base64-encoded, without a `data:` URL prefix.
      #   ASCII whitespace and missing padding are accepted, as by JavaScript's `atob`.
      # @raise [TypeSafeError] `text` isn't valid base64 or decodes to no bytes.
      def self.from_base64(text)
        raise TypeSafeError, "Image data must contain valid base64 text." unless text.is_a?(String)

        # The forgiving-base64 decode that `atob` uses (WHATWG Infra Standard).
        compact = text.b.delete(" \t\n\f\r")
        compact = compact.sub(/={1,2}\z/, "") if (compact.length % 4).zero?
        unless compact.match?(%r{\A[A-Za-z0-9+/]*\z}) && compact.length % 4 != 1
          raise TypeSafeError, "Image data must contain valid base64 text."
        end

        new("#{compact}#{'=' * (-compact.length % 4)}".unpack1("m"))
      end

      # The bytes to send, reading `Pathname` data.
      # @param name [String] the asset's name or reference, for error messages.
      def read(name)
        return @data unless @data.is_a?(Pathname)

        File.binread(@data).freeze
      rescue SystemCallError, IOError => e
        raise TypeSafeError.new("Asset #{name.inspect} could not be read: #{e.message}", cause: e)
      end

      # The unique reference this image is sent under, for referencing it inside text.
      def to_s
        @reference
      end

      # The reference, written wherever the image appears in JSON.
      def to_json(*args)
        @reference.to_json(*args)
      end

      def inspect # :nodoc:
        "#<#{self.class.name} #{@reference}>"
      end

      # The content type whose signature `bytes` start with, or `application/octet-stream`.
      def self.content_type_of(bytes)
        CONTENT_TYPES.each { |type, signature| return type if bytes.b.start_with?(signature) }
        "application/octet-stream"
      end

      private

      def coerce(data)
        case data
        when String then data.b.freeze
        when Pathname then data
        else
          unless data.respond_to?(:read)
            raise TypeSafeError,
                  "Image data must be file bytes (a String), a Pathname, or an IO; got #{data.class}."
          end

          bytes = data.read
          raise TypeSafeError, "Image data read from #{data.class} must be a String." unless bytes.is_a?(String)

          bytes.b.freeze
        end
      end

      def file_size(path)
        File.size(path)
      rescue SystemCallError => e
        raise TypeSafeError.new("Image file could not be read: #{e.message}", cause: e)
      end
    end

    # Text from {SDK.with_assets} or {SDK.join_assets}, with the assets written into it.
    class TextWithAssets
      # The text, with each asset written as its reference.
      attr_reader :text
      # The assets written into the text, including those in nested `TextWithAssets`.
      attr_reader :assets

      def initialize(text, assets)
        @text = text.dup.freeze
        @assets = assets.dup.freeze
      end

      def to_s
        @text
      end

      # The text, written wherever this value appears in JSON.
      def to_json(*args)
        @text.to_json(*args)
      end

      def inspect # :nodoc:
        "#<#{self.class.name} #{@text.inspect}>"
      end

      # Join `parts` into text, as an interpolated string would, and attach the assets among them.
      def self.build(*parts)
        attach(parts.map { |part| stringify(part) }.join, parts)
      end

      # Join `values` with `separator` and attach the assets among them.
      def self.join(values, separator = ",")
        values = values.to_a
        attach(values.map { |value| stringify(value) }.join(separator.to_s), values)
      end

      # `text` with the assets in `values` whose references it contains, in order of appearance.
      def self.attach(text, values)
        interpolated = {}
        collect(values, interpolated, {}.compare_by_identity)
        assets = {}
        text.scan(Assets::REFERENCE) do |reference|
          asset = interpolated[reference]
          assets[reference] = asset if asset
        end
        new(text, assets.values)
      end

      def self.stringify(value)
        value.is_a?(TextWithAssets) ? value.text : value.to_s
      end

      # Add the images in `value`, including those in `TextWithAssets`, to `found` by reference.
      def self.collect(value, found, visited)
        case value
        when Image then found[value.to_s] = value
        when TextWithAssets then value.assets.each { |asset| found[asset.to_s] = asset }
        when Hash, Array
          return if visited.key?(value)

          visited[value] = true
          (value.is_a?(Hash) ? value.values : value).each { |item| collect(item, found, visited) }
        end
      end
    end

    # A `multipart/form-data` request body (RFC 7578) whose first part is a JSON payload.
    class MultipartBody
      # The JSON payload, sent as the `request` part.
      attr_reader :payload
      # The `Content-Type` header value, including the boundary.
      attr_reader :content_type
      # The encoded binary body.
      attr_reader :content

      # @param parts [Array<Hash>] `name`, `content_type`, `content`, and optional `filename`.
      def initialize(payload, parts)
        # A random boundary, as browsers use, is practically certain not to occur in the content.
        boundary = SecureRandom.hex(16)
        content = String.new(encoding: Encoding::BINARY)
        [{ name: "request", content_type: "application/json", content: JSON.generate(payload) }, *parts]
          .each do |part|
          disposition = %(name="#{part[:name]}")
          disposition += %(; filename="#{part[:filename]}") if part[:filename]
          content << "--#{boundary}\r\nContent-Disposition: form-data; #{disposition}\r\n" \
                     "Content-Type: #{part[:content_type]}\r\n\r\n".b << part[:content].b << "\r\n"
        end
        content << "--#{boundary}--\r\n"
        @payload = payload
        @content_type = "multipart/form-data; boundary=#{boundary}"
        @content = content.freeze
      end
    end

    # Request serialization and `multipart/form-data` encoding for assets.
    module Assets
      # Matches `Image#to_s`: the reference an image is sent under.
      REFERENCE = /<image:[0-9a-f]{32}>/

      module_function

      # Validate `assets:` and return it with string names, preserving order.
      def normalize(assets)
        return {} if assets.nil?
        raise TypeSafeError, "`assets` must be a Hash of names to images." unless assets.is_a?(Hash)

        assets.each_with_object({}) do |(name, asset), normalized|
          key = name.to_s
          raise TypeSafeError, "Asset names must be nonempty." if key.empty?
          unless asset.is_a?(Image)
            raise TypeSafeError,
                  "Asset #{key.inspect} must be an image created with Typesafe::SDK.image, got #{asset.class}."
          end

          normalized[key] = asset
        end
      end

      # Serialize `payload` to JSON, writing each image as its name in `assets`, or else as its
      # reference, and collect the assets the request sends.
      #
      # The assets are those in `assets`, then each image whose reference appears in the JSON, in
      # order of appearance. Non-finite floats are sent as the strings `NaN`, `Infinity`, and
      # `-Infinity`, as the JavaScript SDK does.
      #
      # @return [Array(String, Hash{String => Image}, nil)] the JSON and the assets to send.
      # @raise [TypeSafeError] the payload holds a cycle, a reference of an image not attached to
      #   the request, or doesn't contain the name of an image in `assets`.
      def serialize_request(payload, assets = {})
        # An image under several names is written as the last one.
        names = {}.compare_by_identity
        assets.each { |name, asset| names[asset] = name }
        known = assets.values.to_h { |asset| [asset.to_s, asset] }
        json = JSON.generate(prepare(payload, names, known, {}.compare_by_identity))

        unreferenced = assets.keys.reject { |name| json.include?(JSON.generate(name)[1..-2]) }
        unless unreferenced.empty?
          raise TypeSafeError,
                "Assets not referenced in the request: #{unreferenced.join(', ')}. " \
                "Write each name in `assets` into `state`, question instructions, or criteria."
        end

        sent = assets.dup
        missing = []
        json.scan(REFERENCE) do |reference|
          next if sent.key?(reference)

          asset = known[reference]
          asset ? sent[reference] = asset : missing << reference
        end
        unless missing.empty?
          raise TypeSafeError,
                "Image references without an attached image: #{missing.uniq.join(', ')}. " \
                "Join images into text with Typesafe::SDK.with_assets instead of string interpolation."
        end

        [json, sent.empty? ? nil : sent]
      end

      # A JSON-ready copy of `value` with assets written as names or references.
      def prepare(value, names, known, path)
        case value
        when Image
          name = names[value]
          return name if name

          known[value.to_s] = value
          value.to_s
        when TextWithAssets
          value.assets.reduce(value.text) do |text, asset|
            name = names[asset]
            known[asset.to_s] = asset unless name
            name ? text.gsub(asset.to_s) { name } : text
          end
        when Float
          value.finite? ? value : value.to_s
        when Hash, Array
          raise TypeSafeError, "The request contains a circular reference." if path.key?(value)

          path[value] = true
          begin
            if value.is_a?(Hash)
              value.to_h { |key, item| [key.to_s, prepare(item, names, known, path)] }
            else
              value.map { |item| prepare(item, names, known, path) }
            end
          ensure
            path.delete(value)
          end
        else
          value
        end
      end

      # A multipart body whose `request` part is `payload` with `assets` added, followed by each
      # asset's file bytes in its own part. The API accepts each part for only one asset, so an
      # image under several references is sent once per reference.
      #
      # @raise [TypeSafeError] a `Pathname` image can't be read.
      def encode(payload, assets)
        parts = []
        entries = {}
        assets.each do |name, asset|
          bytes = asset.read(name)
          part = "asset-#{parts.length}"
          parts << { name: part, content_type: Image.content_type_of(bytes), content: bytes, filename: part }
          entries[name] = { "type" => asset.type, "part" => part }
        end
        MultipartBody.new(payload.merge("assets" => entries), parts)
      end
    end
  end
end
