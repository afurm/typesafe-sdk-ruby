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

    # An answer, keeping every field the API returned, including fields not modeled here.
    class Answer
      attr_reader :type

      def initialize(data)
        @data = data
        @type = data["type"]
      end

      # The answer as the API returned it, with string keys.
      def to_h
        @data.dup
      end
    end

    # Token usage for a request. Each count is `nil` when the API did not report it.
    class Usage
      attr_reader :input_tokens, :output_tokens

      def initialize(data)
        @input_tokens = data["input_tokens"]
        @output_tokens = data["output_tokens"]
      end
    end

    # A yes/no answer.
    class NoulResponse < Answer
      attr_reader :noul

      def initialize(data)
        super
        @noul = data["noul"]
      end
    end

    # A selected label with its probabilities.
    class ChoiceResponse < Answer
      attr_reader :choice, :confidence, :probabilities

      def initialize(data)
        super
        @choice = data["choice"]
        @confidence = data["confidence"]
        @probabilities = data["probabilities"]
      end
    end

    # An expected score with its rubric and probabilities.
    class ScoreResponse < Answer
      attr_reader :score, :confidence, :legend, :probabilities

      def initialize(data)
        super
        @score = data["score"]
        @confidence = data["confidence"]
        @legend = data["legend"]
        @probabilities = data["probabilities"]
      end
    end

    # A box's edges as fractions of the image's height (`top`, `bottom`) and width
    # (`left`, `right`), each from zero to one.
    class BoxCoordinates
      attr_reader :top, :bottom, :left, :right

      def initialize(data)
        @top = data["top"]
        @bottom = data["bottom"]
        @left = data["left"]
        @right = data["right"]
      end

      def to_h
        { "top" => top, "bottom" => bottom, "left" => left, "right" => right }
      end
    end

    # The answer to a box question.
    class BoxResponse < Answer
      # Where the instructions' subject is in the image, or `nil` when absent.
      attr_reader :box
      # Confidence in the box, from zero to one, or `nil` when the API didn't report it.
      attr_reader :confidence

      def initialize(data)
        super
        @box = data["box"].is_a?(Hash) ? BoxCoordinates.new(data["box"]) : nil
        @confidence = data["confidence"]
      end
    end

    # Builds the answer object matching the question type.
    module ResponseFactory
      CLASSES = {
        "noul" => NoulResponse,
        "choice" => ChoiceResponse,
        "score" => ScoreResponse,
        "box" => BoxResponse
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
