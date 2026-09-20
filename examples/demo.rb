# Run with `TYPESAFE_API_KEY=... ruby examples/demo.rb`.
# frozen_string_literal: true

require "typesafe-sdk-ruby"

client = Typesafe::SDK::Client.new(log_level: :info)

models = client.models.list
puts "Available models: #{models.map(&:name).join(', ')}"

ticket = {
  subject: "Charged twice this month",
  body: "Hi, I see two charges of $49 on my card for August. " \
        "I only have one account. Please fix this ASAP, I'm pretty frustrated."
}

begin
  response = client.system_one(
    state: ticket,
    questions: {
      is_billing: Typesafe::SDK.noul("Is this ticket about billing?"),
      sentiment: Typesafe::SDK.choice("What is the customer's tone?", {
                                        calm: nil,
                                        frustrated: nil,
                                        angry: nil
                                      }),
      urgency: Typesafe::SDK.score("How urgent is this ticket?",
                                   ["can wait", "this week", "today", "right now"]),
      refund_risk: Typesafe::SDK.score("How likely is the customer to demand a refund?",
                                       %w[unlikely possible likely])
    }
  )

  answers = response.answers
  puts "billing?     #{format('%.2f', answers['is_billing'].noul)}"
  sentiment = answers["sentiment"]
  puts "tone         #{sentiment.choice} (#{format('%.2f', sentiment.probabilities[sentiment.choice])})"
  urgency = answers["urgency"]
  puts "urgency      #{format('%.2f', urgency.score)} on a 0-3 scale: #{urgency.legend.inspect}"
  refund = answers["refund_risk"]
  puts "refund risk  #{format('%.2f', refund.score)} (#{format('%.2f', refund.confidence)} confidence)"
  puts "tokens       #{response.usage.input_tokens} in / #{response.usage.output_tokens} out"
rescue Typesafe::SDK::APIError => e
  warn "API error #{e.status} (request #{e.request_id || 'unknown'}): #{e.body.inspect}"
end
