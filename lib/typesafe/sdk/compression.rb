# frozen_string_literal: true

module Typesafe
  module SDK
    # Request body compression with zstd, provided by the optional `zstd-ruby` gem.
    module Compression
      # Bodies below this many bytes fit in a single TCP segment, so they are sent uncompressed.
      MIN_COMPRESSED_BODY_BYTES = 1024

      module_function

      # Whether the `zstd-ruby` gem can be loaded. Checked once per process.
      def available?
        return @available unless @available.nil?

        @available = begin
          require "zstd-ruby"
          true
        rescue LoadError
          false
        end
      end

      # Resolve the `compression:` option to the `Content-Encoding` request bodies are sent with:
      # `:zstd` when the runtime has it, otherwise `false`.
      #
      # @raise [TypeSafeError] the value isn't a supported option, or zstd is unavailable.
      def resolve(compression)
        return available? ? :zstd : false if compression.nil?
        return false if compression == false

        unless [:zstd, "zstd"].include?(compression)
          raise TypeSafeError, "`compression` must be :zstd or false, got #{compression.inspect}."
        end
        unless available?
          raise TypeSafeError,
                "zstd compression requires the zstd-ruby gem. Add it to your Gemfile or pass " \
                "`compression: false` instead."
        end

        :zstd
      end

      # Compress a request body with zstd.
      def compress(body)
        Zstd.compress(body).b
      end
    end
  end
end
