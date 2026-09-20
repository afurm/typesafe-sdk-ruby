# frozen_string_literal: true

require_relative "typesafe/sdk/version"
require_relative "typesafe/sdk/env"
require_relative "typesafe/sdk/logging"
require_relative "typesafe/sdk/retry"
require_relative "typesafe/sdk/errors"
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
  end
end
