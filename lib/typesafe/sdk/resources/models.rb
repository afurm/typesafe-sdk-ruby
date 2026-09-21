# frozen_string_literal: true

module Typesafe
  module SDK
    module Resources
      # Access to the Models API resource.
      class Models
        def initialize(client)
          @client = client
        end

        # List the models available to the account.
        #
        # @param options [Hash] per-call `timeout`, `retry_policy`, `headers`, and `signal` settings.
        # @param with_response [Boolean] return model cards with HTTP metadata and request ID.
        # @return [Array<ModelCard>, WithResponse]
        # @raise [TypeSafeError] the response shape is unexpected.
        # @raise [APIError] the server returns a non-2xx response after retries.
        def list(with_response: false, **options)
          response = @client.request(:get, "/v1/models", **options)
          wire = response.body
          unless wire.is_a?(Hash) && wire["models"].is_a?(Array)
            raise TypeSafeError,
                  "Unexpected response shape from GET /v1/models; expected { models: [...] }."
          end

          result = wire["models"].map { |card| ModelCard.new(card) }
          with_response ? WithResponse.new(result, response) : result
        end
      end
    end
  end
end
