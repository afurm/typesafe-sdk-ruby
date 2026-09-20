# frozen_string_literal: true

module Typesafe
  module SDK
    # Builders and validation for the three question types.
    module Questions
      module_function

      # Create a yes/no question with optional descriptions for either outcome.
      #
      # @param instructions [String, Hash, Array, nil] the question; defaults to `nil`.
      # @param criteria [Hash, nil] optional descriptions of the yes and no outcomes.
      def noul(instructions = nil, criteria: nil)
        { type: "noul", instructions: instructions, criteria: criteria }
      end

      # Create a score question using an ordered rubric.
      #
      # @param instructions [String, Hash, Array, nil] the question.
      # @param criteria [Array] at least two descriptions indexed by score from zero.
      def score(instructions, criteria)
        unless criteria.is_a?(Array)
          raise TypeSafeError,
                "Score criteria must be a list of descriptions indexed by score from zero, " \
                "not a map."
        end

        { type: "score", instructions: instructions, criteria: criteria }
      end

      # Create a question that selects between named alternatives.
      #
      # @param instructions [String, Hash, Array, nil] the question.
      # @param criteria [Hash] labels mapped to descriptions, or `nil` for undescribed labels.
      def choice(instructions, criteria)
        if criteria.is_a?(Array)
          raise TypeSafeError, "Choice criteria must be a map of labels to descriptions, not a list."
        end

        { type: "choice", instructions: instructions, criteria: criteria }
      end

      # Reject empty question sets and score questions without a list of at least two criteria.
      def validate!(questions)
        raise TypeSafeError, "At least one question is required." if questions.empty?

        questions.each do |name, question|
          next unless question.is_a?(Hash) && question[:type] == "score"

          criteria = question[:criteria]
          unless criteria.is_a?(Array)
            raise TypeSafeError,
                  "Score question \"#{name}\" has criteria that are not a list; " \
                  "score criteria must be a list of descriptions indexed by score from zero."
          end
          next unless criteria.length < 2

          raise TypeSafeError,
                "Score question \"#{name}\" has #{criteria.length} criteria; " \
                "at least two scores are required."
        end
      end
    end
  end
end
