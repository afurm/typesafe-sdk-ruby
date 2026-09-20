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
        # @param options [Hash] per-call `timeout`, `retry`, `headers`, and `signal` settings.
        # @return [Array<ModelCard>]
        # @raise [TypeSafeError] the response shape is unexpected.
        # @raise [APIError] the server returns a non-2xx response after retries.
        def list(**options)
          response = @client.request(:get, "/v1/models", **options)
          wire = response.body
          unless wire.is_a?(Hash) && wire["models"].is_a?(Array)
            raise TypeSafeError,
                  "Unexpected response shape from GET /v1/models; expected { models: [...] }."
          end

          wire["models"].map { |card| ModelCard.new(card) }
        end
      end
    end
  end
end
