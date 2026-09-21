# frozen_string_literal: true

module Typesafe
  module SDK
    # Parsed data together with HTTP metadata, like the JS SDK withResponse() result.
    class WithResponse
      attr_reader :data, :response, :request_id

      def initialize(data, response)
        @data = data
        @response = response
        @request_id = response.request_id
      end
    end

    # Token usage for a request.
    class Usage
      attr_reader :input_tokens, :output_tokens

      def initialize(data)
        @input_tokens = data["input_tokens"]
        @output_tokens = data["output_tokens"]
      end
    end

    # A yes/no answer.
    class NoulResponse
      attr_reader :type, :noul

      def initialize(data)
        @type = data["type"]
        @noul = data["noul"]
      end
    end

    # A selected label with its probabilities.
    class ChoiceResponse
      attr_reader :type, :choice, :confidence, :probabilities

      def initialize(data)
        @type = data["type"]
        @choice = data["choice"]
        @confidence = data["confidence"]
        @probabilities = data["probabilities"]
      end
    end

    # An expected score with its rubric and probabilities.
    class ScoreResponse
      attr_reader :type, :score, :confidence, :legend, :probabilities

      def initialize(data)
        @type = data["type"]
        @score = data["score"]
        @confidence = data["confidence"]
        @legend = data["legend"]
        @probabilities = data["probabilities"]
      end
    end

    # Builds the answer object matching the question type.
    module ResponseFactory
      CLASSES = {
        "noul" => NoulResponse,
        "choice" => ChoiceResponse,
        "score" => ScoreResponse
      }.freeze

      module_function

      def build(data)
        klass = CLASSES[data["type"]]
        raise TypeSafeError, "Unknown answer type #{data['type'].inspect}." unless klass

        klass.new(data)
      end
    end

    # Answers keyed by question name, with model and usage metadata.
    class SystemOneResult
      attr_reader :model, :answers, :usage

      def initialize(data)
        @model = data["model"]
        @answers = (data["answers"] || {}).transform_values { |a| ResponseFactory.build(a) }
        @usage = Usage.new(data["usage"] || {})
      end

      # Access an answer by question name (symbol or string).
      def [](name)
        @answers[name.to_s]
      end
    end

    # Metadata for an available model.
    class ModelCard
      attr_reader :name, :description, :release_date

      def initialize(data)
        @name = data["name"]
        @description = data["description"]
        @release_date = data["release_date"]
      end
    end
  end
end
