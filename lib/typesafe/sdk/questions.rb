# frozen_string_literal: true

module Typesafe
  module SDK
    # Builders and validation for the three question types.
    module Questions
      MAX_SCORE_LEVELS = 10
      MAX_CHOICE_OPTIONS = 255

      module_function

      # Create a yes/no question. Supply instructions or at least one outcome description.
      # @param instructions [String, Hash, Array, nil]
      # @param criteria [Hash, nil] optional true/false outcome descriptions.
      def noul(instructions = nil, criteria: nil)
        question = { type: "noul", instructions: instructions, criteria: criteria }
        validate_noul!(instructions, criteria, "noul")
        question
      end

      # Create a score question with 2–10 ordered descriptions. Nil levels are not supported.
      # An empty string preserves a position without a description.
      def score(instructions, criteria)
        validate_score!(criteria, "score")
        { type: "score", instructions: instructions, criteria: criteria }
      end

      # Create a choice between 1–255 named options; nil leaves a label undescribed.
      def choice(instructions, criteria)
        validate_choice!(criteria, "choice")
        { type: "choice", instructions: instructions, criteria: criteria }
      end

      def validate_state!(state)
        return if state.is_a?(String) || state.is_a?(Hash) || state.is_a?(Array)

        raise TypeSafeError, "`state` must be a string, object, or array; nil is not supported."
      end

      # Validate builders and raw JSON-style questions without altering the caller's data.
      def validate!(questions)
        raise TypeSafeError, "At least one question is required." unless questions.is_a?(Hash) && !questions.empty?

        questions.each do |name, question|
          raise TypeSafeError, "Question key cannot be empty." if name.to_s.empty?
          raise TypeSafeError, "Question must be an object." unless question.is_a?(Hash)

          wire = question.transform_keys(&:to_s)
          case wire["type"].to_s
          when "score" then validate_score!(wire["criteria"], name)
          when "choice" then validate_choice!(wire["criteria"], name)
          when "noul" then validate_noul!(wire["instructions"], wire["criteria"], name)
          end
        end
      end

      def validate_noul!(instructions, criteria, name)
        descriptions = criteria.is_a?(Hash) ? criteria.transform_keys(&:to_s) : {}
        return unless instructions.nil? && %w[true false].all? { |key| descriptions[key].nil? }

        raise TypeSafeError, "Noul question #{name.inspect} must have instructions or criteria."
      end

      def validate_score!(criteria, name)
        unless criteria.is_a?(Array)
          raise TypeSafeError,
                "Score question #{name.inspect} has criteria that are not a list; " \
                "score criteria must be a list of descriptions indexed by score from zero."
        end
        raise TypeSafeError, "Score question #{name.inspect}: at least two scores are required." if criteria.length < 2
        if criteria.length > MAX_SCORE_LEVELS
          raise TypeSafeError, "Score question #{name.inspect}: at most #{MAX_SCORE_LEVELS} levels are allowed."
        end
        return unless criteria.any?(&:nil?)

        raise TypeSafeError,
              "Score question #{name.inspect} contains a nil level; use a description or an empty string " \
              "to preserve its position."
      end

      def validate_choice!(criteria, name)
        unless criteria.is_a?(Hash)
          raise TypeSafeError, "Choice criteria must be a map of labels to descriptions, not a list."
        end
        return if criteria.length.between?(1, MAX_CHOICE_OPTIONS)

        raise TypeSafeError, "Choice question #{name.inspect} requires 1–#{MAX_CHOICE_OPTIONS} options."
      end
    end
  end
end
