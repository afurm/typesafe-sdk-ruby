# frozen_string_literal: true

require "spec_helper"

RSpec.describe Typesafe::SDK::Questions do
  describe ".noul" do
    it "requires instructions or criteria" do
      expect { described_class.noul }.to raise_error(Typesafe::SDK::TypeSafeError, /instructions or criteria/)
    end

    it "accepts instructions and criteria" do
      q = described_class.noul("Is this billing?", criteria: { true: "money", false: "other" })
      expect(q[:type]).to eq("noul")
      expect(q[:instructions]).to eq("Is this billing?")
      expect(q[:criteria]).to eq(true: "money", false: "other")
    end
  end

  describe ".score" do
    it "builds a score question" do
      q = described_class.score("How urgent?", ["can wait", "today"])
      expect(q).to eq(type: "score", instructions: "How urgent?", criteria: ["can wait", "today"])
    end

    it "rejects a map of criteria" do
      expect { described_class.score("q", { low: "low" }) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /must be a list/)
    end
  end

  describe ".choice" do
    it "builds a choice question" do
      q = described_class.choice("Tone?", { calm: nil, angry: nil })
      expect(q).to eq(type: "choice", instructions: "Tone?", criteria: { calm: nil, angry: nil })
    end

    it "rejects a list of criteria" do
      expect { described_class.choice("q", %w[a b]) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /must be a map/)
    end
  end

  describe ".validate!" do
    it "rejects an empty question set" do
      expect { described_class.validate!({}) }
        .to raise_error(Typesafe::SDK::TypeSafeError, "At least one question is required.")
    end

    it "rejects score criteria shorter than two entries" do
      questions = { bad: { type: "score", instructions: nil, criteria: ["one"] } }
      expect { described_class.validate!(questions) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /at least two scores are required/)
    end

    it "rejects score criteria that are not a list" do
      questions = { bad: { type: "score", instructions: nil, criteria: { "0" => "x" } } }
      expect { described_class.validate!(questions) }
        .to raise_error(Typesafe::SDK::TypeSafeError, /not a list/)
    end

    it "accepts valid questions" do
      questions = {
        billing: described_class.noul("Is this billing?"),
        tone: described_class.choice("Tone?", { calm: nil }),
        urgency: described_class.score("Urgent?", %w[low high])
      }
      expect { described_class.validate!(questions) }.not_to raise_error
    end
  end
end
