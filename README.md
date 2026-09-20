# Unofficial TypeSafe AI Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/typesafe-sdk-ruby)](https://rubygems.org/gems/typesafe-sdk-ruby)
[![CI](https://github.com/afurm/typesafe-sdk-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/afurm/typesafe-sdk-ruby/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Community-maintained, unofficial** Ruby SDK for [TypeSafe AI](https://typesafe.ai). Ask named
questions about text or structured state and get typed answers back: yes/no (noul), choice, and
score questions — with retries, timeouts, structured logging, and typed errors.

> This gem is not affiliated with, endorsed by, or supported by TypeSafe AI. It is a faithful
> community port of the official [JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js).
> Official SDKs: [JavaScript](https://github.com/typesafe-ai/typesafe-sdk-js) and Python.

> **Versioning:** gem versions intentionally mirror the official JavaScript SDK so it is
> obvious which upstream release each port tracks (e.g. gem 0.6.0 ≈ JS SDK 0.6.0).

## Requirements

- Ruby 3.1 or newer
- A TypeSafe API key (`TYPESAFE_API_KEY`)

## Installation

Install the gem:

```sh
gem install typesafe-sdk-ruby
```

Or add it to your application's `Gemfile`:

```ruby
gem "typesafe-sdk-ruby"
```

and run `bundle install`.

## Quickstart

```ruby
require "typesafe-sdk-ruby"

client = Typesafe::SDK::Client.new

response = client.system_one(
  state: { document: "I was charged twice. Please fix this ASAP." },
  questions: {
    category: Typesafe::SDK.choice("What is this ticket about?", {
      billing: nil,
      technical: nil,
      other: nil,
    }),
  },
)

puts response.answers["category"].choice
```

Answer objects are typed by the question that produced them:

| Question | Answer class | Key fields |
| --- | --- | --- |
| `noul` | `Typesafe::SDK::NoulResponse` | `noul` (probability of yes) |
| `choice` | `Typesafe::SDK::ChoiceResponse` | `choice`, `confidence`, `probabilities` |
| `score` | `Typesafe::SDK::ScoreResponse` | `score`, `confidence`, `legend`, `probabilities` |

## Configuration

Explicit options take precedence over environment variables, then SDK defaults.

| Option | Environment variable | Default |
| --- | --- | --- |
| `api_key:` | `TYPESAFE_API_KEY` | — (required) |
| `base_url:` | `TYPESAFE_BASE_URL` | `https://api.typesafe.ai` |
| `default_model:` | `TYPESAFE_DEFAULT_MODEL` | `jev-latest` |
| `log_level:` | `TYPESAFE_LOG_LEVEL` | `warn` |

```ruby
client = Typesafe::SDK::Client.new(
  api_key: "sk-...",
  base_url: "https://api.typesafe.ai",
  default_model: "jev-latest",
  log_level: :info,          # :debug, :info, :warn, :error, :off
  timeout: 10,               # seconds per attempt
  retry_policy: { max_retries: 2, backoff_initial_ms: 500 },
  default_headers: { "X-My-Header" => "value" },
)
```

## Retries and timeouts

The SDK retries HTTP `408`, `429`, and `5xx` responses plus connection failures and timeouts,
with capped exponential backoff and jitter. It honors `Retry-After` and `retry-after-ms`
headers up to a cap. Every option is overridable per client or per call:

```ruby
client.system_one(
  state: "...",
  questions: { ... },
  timeout: 30,
  retry_policy: { max_retries: 0 },  # disable retries for this call
)
```

## Error handling

```ruby
begin
  client.system_one(state: "...", questions: { ... })
rescue Typesafe::SDK::RateLimitError => e
  retry_after e.retry_after_ms
rescue Typesafe::SDK::APIError => e
  warn "API error #{e.status} (request #{e.request_id}): #{e.body}"
end
```

Error hierarchy:

- `Typesafe::SDK::TypeSafeError` — base class
  - `Typesafe::SDK::APIError` — non-2xx HTTP responses
    - `BadRequestError` (400), `AuthenticationError` (401), `PermissionDeniedError` (403),
      `NotFoundError` (404), `UnprocessableEntityError` (422), `RateLimitError` (429),
      `InternalServerError` (5xx)
  - `Typesafe::SDK::APIConnectionError` — DNS, TLS, connection failures
    - `Typesafe::SDK::APITimeoutError`
  - `Typesafe::SDK::APIUserAbortError` — caller cancellation

## Cancellation

```ruby
signal = Typesafe::SDK::Signal.new
Thread.new { sleep 5; signal.cancel }

client.system_one(state: "...", questions: { ... }, signal: signal)
# raises Typesafe::SDK::APIUserAbortError once canceled
```

## Listing models

```ruby
client.models.list.each do |model|
  puts "#{model.name}: #{model.description}"
end
```

## Logging

The default logger writes to `$stderr` with a `[typesafe-sdk-ruby]` prefix. `info` logs request
summaries; `debug` adds headers (credentials redacted) and bodies. Pass any object responding
to `debug`/`info`/`warn`/`error`:

```ruby
client = Typesafe::SDK::Client.new(logger: Rails.logger, log_level: :info)
```

## Ruby on Rails

The gem is framework-agnostic and works out of the box in Rails. A common pattern is a
wrapped initializer:

```ruby
# config/initializers/typesafe.rb
TYPESAFE = Typesafe::SDK::Client.new(log_level: :info)
```

```ruby
# app/models/concerns/typesafe_classifiable.rb
module TypesafeClassifiable
  def classify(text)
    TYPESAFE.system_one(
      state: text,
      questions: {
        category: Typesafe::SDK.choice("Category?", {
          billing: nil, technical: nil, other: nil,
        }),
      },
    ).answers["category"].choice
  end
end
```

## Development

```sh
bundle install
bundle exec rake        # specs + RuboCop
bundle exec rspec       # specs only
bundle exec rubocop     # lint only
```

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/afurm/typesafe-sdk-ruby/issues). See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
