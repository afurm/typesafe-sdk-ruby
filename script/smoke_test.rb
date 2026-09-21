# frozen_string_literal: true

# Explicitly opt in: this makes one billable inference request with synthetic data.
abort "Set TYPESAFE_LIVE_TEST=1 and TYPESAFE_API_KEY to run the live smoke test" unless ENV["TYPESAFE_LIVE_TEST"] == "1"
require_relative "../lib/typesafe-sdk-ruby"

client = Typesafe::SDK::Client.new(log_level: :off, retry_policy: { max_retries: 0 })
models = client.models.list
abort "No models returned" if models.empty?
result = client.system_one(
  state: "The customer was charged twice and requests a refund.",
  questions: {
    billing: Typesafe::SDK.noul("Is this about billing?"),
    category: Typesafe::SDK.choice("Category?", billing: nil, other: nil),
    urgency: Typesafe::SDK.score("Urgency?", %w[low high])
  }, with_response: true
)
abort "Missing typed answers" unless result.data[:billing].is_a?(Typesafe::SDK::NoulResponse) &&
                                     result.data[:category].is_a?(Typesafe::SDK::ChoiceResponse) &&
                                     result.data[:urgency].is_a?(Typesafe::SDK::ScoreResponse)
puts "Live smoke test passed; model=#{result.data.model}, request_id=#{result.request_id}"
