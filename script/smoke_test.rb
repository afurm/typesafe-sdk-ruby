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

# Images are experimental; TYPESAFE_LIVE_IMAGES=1 adds one more billable request with a box question.
if ENV["TYPESAFE_LIVE_IMAGES"] == "1"
  # A 512x512 white PNG with a red square from 128 to 384 pixels on each axis.
  square = Typesafe::SDK::Image.from_base64(
    "iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQMAAADOtka5AAAABlBMVEX/////AADrWueTAAAAZ0lEQVR42u3MQQ0AAAgEoOtf" \
    "WiM4N/1BABIAAAAAAAAAgGM1EAgEAoFAIBAIBAKBQCAQCAQCgUAgEAgEAoFAIBAIBAKBQCAQCAQCgUAgEAgEAoFAIBAIBAKB" \
    "QCD4DgAAAAAAAAAAlhrvN+HSAmCw9gAAAABJRU5ErkJggg=="
  )
  images = Typesafe::SDK::Client.new(log_level: :off, retry_policy: { max_retries: 0 }, timeout: 120,
                                     default_headers: { "TypeSafe-Danger-Zone-Images" => "true" })
  answer = images.system_one(state: square, questions: { square: Typesafe::SDK.box("The red square") },
                             model: "jev-preview")[:square]
  edges = answer.box&.to_h&.values || []
  abort "Missing box answer" unless answer.is_a?(Typesafe::SDK::BoxResponse) && edges.length == 4 &&
                                    edges.all? { |edge| edge.is_a?(Numeric) && edge.between?(0, 1) }
  puts "Live image smoke test passed"
end
