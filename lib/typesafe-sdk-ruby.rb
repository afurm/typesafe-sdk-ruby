# frozen_string_literal: true

require_relative "typesafe/sdk/version"
require_relative "typesafe/sdk/env"
require_relative "typesafe/sdk/logging"
require_relative "typesafe/sdk/retry"
require_relative "typesafe/sdk/errors"
require_relative "typesafe/sdk/assets"
require_relative "typesafe/sdk/compression"
require_relative "typesafe/sdk/questions"
require_relative "typesafe/sdk/http"
require_relative "typesafe/sdk/types"
require_relative "typesafe/sdk/client"
require_relative "typesafe/sdk/resources/models"

module Typesafe
  # Ruby SDK for the TypeSafe AI API.
  module SDK
    module_function

    # Create a client, reading configuration from the environment when omitted.
    # @see Client#initialize
    def new_client(**options)
      Client.new(**options)
    end

    # Create a yes/no question. @see Questions.noul
    def noul(instructions = nil, criteria: nil)
      Questions.noul(instructions, criteria: criteria)
    end

    # Create a score question. @see Questions.score
    def score(instructions, criteria)
      Questions.score(instructions, criteria)
    end

    # Create a choice question. @see Questions.choice
    def choice(instructions, criteria)
      Questions.choice(instructions, criteria)
    end

    # Create a box question. @see Questions.box
    def box(instructions = nil)
      Questions.box(instructions)
    end

    # Create a PNG or JPEG image asset from file bytes, a Pathname, or an IO.
    # Use {Image.from_base64} for base64 text. @see Image#initialize
    def image(data)
      Image.new(data)
    end

    # Join text and images into text that carries its images, like JavaScript's `withAssets`
    # tagged template. Other values are converted with `to_s`, as string interpolation does.
    #
    # @example
    #   Typesafe::SDK.with_assets("Does ", photo, " show the product in ", listing, "?")
    # @return [TextWithAssets]
    def with_assets(*parts)
      TextWithAssets.build(*parts)
    end

    # Join `values` with `separator` (default `","`, as in JavaScript's `withAssets.join`) into
    # text that carries the images among them.
    # @return [TextWithAssets]
    def join_assets(values, separator = ",")
      TextWithAssets.join(values, separator)
    end
  end
end
