# Unofficial TypeSafe AI Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/typesafe-sdk-ruby)](https://rubygems.org/gems/typesafe-sdk-ruby)
[![CI](https://github.com/afurm/typesafe-sdk-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/afurm/typesafe-sdk-ruby/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A community-maintained Ruby client for [TypeSafe AI](https://typesafe.ai), with typed answer
objects, retries, timeouts, cancellation, and configurable logging.

TypeSafe's Jev model evaluates state against questions defined by your application. It returns
structured decisions that your code can use for classification, ranking, and routing.
Read the [official introduction](https://docs.typesafe.ai/introduction) for the product model.

**Unofficial:** this project is not affiliated with, endorsed by, or supported by TypeSafe AI.
It targets the official [JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js)
**0.6.0**. Official [JavaScript and Python SDKs](https://docs.typesafe.ai/sdk) are maintained
by TypeSafe AI.

**Release status:** this README follows `main`. Ruby **0.6.0.1** is currently unreleased;
its fixes, stricter validation, new error classes, `with_response:`, and `extra_body:`
are not in the published 0.6.0 gem.
See the [changelog](CHANGELOG.md) and [releases](https://github.com/afurm/typesafe-sdk-ruby/releases).
Ruby-only corrections add a fourth version component: `0.6.0.1` still targets JS `0.6.0`.

## Installation

Requires Ruby **3.1 or newer**; CI tests Ruby 3.1, 3.2, 3.3, 3.4, and 4.0.

```sh
gem install typesafe-sdk-ruby
```

For Bundler, add the gem to your application's `Gemfile` and run `bundle install`:

```ruby
gem "typesafe-sdk-ruby"
```

Create an API key in the [TypeSafe console](https://console.typesafe.ai/), then set
`TYPESAFE_API_KEY` in your environment or application secret store. The SDK reads it
automatically. See the [official quick start](https://docs.typesafe.ai/introduction/quickstart).

## Quickstart

```ruby
require "typesafe-sdk-ruby"

client = Typesafe::SDK::Client.new
response = client.system_one(
  state: { document: "I was charged twice. Please fix this ASAP." },
  questions: {
    category: Typesafe::SDK.choice("What is this ticket about?", {
      billing: "Payments, invoices, or refunds",
      technical: "A product error or technical problem",
      other: "A different subject",
    }),
  },
)

category = response[:category]
puts category.choice
puts category.confidence
puts category.probabilities
puts response.model
puts response.usage.input_tokens
```

`response[:category]` and `response["category"]` work interchangeably.
`response.answers` is a regular Hash with string keys.

## Choosing a question type

| Builder | Use it for | Result |
| --- | --- | --- |
| `noul` | A yes/no judgment | `noul`: probability of yes, from 0 to 1 |
| `choice` | Selecting one named option | `choice`, `probabilities`, `confidence` |
| `score` | Rating against ordered descriptions | `score`, `legend`, `probabilities`, `confidence` |

Mix question types in a single call. Each question is evaluated against the same state,
independently of the other questions. Put the meaning in the instructions and criteria;
question IDs identify answers and are not used for inference.
See [primitives](https://docs.typesafe.ai/primitives) and the [API reference](https://docs.typesafe.ai/api).

```ruby
response = client.system_one(
  state: "The export fails in Safari, but I can finish the task in Firefox.",
  questions: {
    workaround: Typesafe::SDK.noul("Does the user describe a working alternative?"),
    category: Typesafe::SDK.choice("Which area is affected?", {
      export: "Exporting application data",
      login: "Signing in to the application",
      other: "Another area",
    }),
    severity: Typesafe::SDK.score("How much does this issue affect the user's task?", [
      "The task works; only its appearance is affected",
      "The task needs an alternative method to complete",
      "The task cannot be completed",
    ]),
  },
)

puts response[:workaround].noul
puts response[:severity].score
puts response[:severity].probabilities["1"]
puts response[:severity].legend["1"]
```

Score criteria are an **ordered array**, with positions starting at zero. A returned score
is a probability-weighted mean and can be fractional. `legend` and `probabilities` retain
string keys such as `"0"` and `"1"`. See the [Score guide](https://docs.typesafe.ai/primitives/score).

State, instructions, and criterion descriptions can also contain JSON objects or arrays.
Optional noul criteria can describe either outcome:

```ruby
question = Typesafe::SDK.noul("Is this an explicit cancellation request?", criteria: {
  true: "The customer asks to end the subscription",
  false: "The customer only asks about cancellation terms",
})
```

See [structured questions](https://docs.typesafe.ai/primitives/advanced) for more examples.

From Ruby **0.6.0.1**, builders and raw question hashes are checked before sending:

- State must be a string, object, or array; `nil` is rejected, while `""`, `{}`, and `[]` are allowed.
- Noul needs instructions or at least one non-nil true/false outcome description.
- Score needs **2–10** levels. A nil level is rejected; use `""` explicitly to keep an
  undescribed position. The SDK never drops or renumbers levels.
- Choice needs **1–255** options. Nil descriptions remain valid for choice labels.
- Question names must not be empty strings.

Failures raise `Typesafe::SDK::TypeSafeError` without an HTTP request. These checks address
request shapes reported as rejected by the API, even though JS 0.6.0 accepts them locally.
See the [upstream issue audit](docs/UPSTREAM_ISSUES.md) for evidence and limitations.

## Using confidence

Choice and Score include confidence derived from their probability distributions. Confidence
is distinct from the probability of the selected option and is not a guarantee of correctness.
Noul returns the probability of yes and has no separate confidence field.
See the [official confidence guide](https://docs.typesafe.ai/confidence).

```ruby
category = response[:category]
threshold = 0.8 # Illustrative: evaluate a suitable threshold on your own labeled examples.
puts(category.confidence >= threshold ? "Route to #{category.choice}" : "Needs review")
```

## Configuration

Explicit options take precedence over environment variables, then SDK defaults.
Blank environment values are ignored for optional settings. An API key is required.
From Ruby 0.6.0.1, outer spaces, tabs, and line endings are trimmed from keys; blank keys,
non-ASCII text, embedded whitespace, and control characters raise `TypeSafeError` at
construction. Error messages do not include the key.

| Option | Environment variable | Default |
| --- | --- | --- |
| `api_key:` | `TYPESAFE_API_KEY` | Required |
| `base_url:` | `TYPESAFE_BASE_URL` | `https://api.typesafe.ai` |
| `default_model:` | `TYPESAFE_DEFAULT_MODEL` | `jev-latest` |
| `log_level:` | `TYPESAFE_LOG_LEVEL` | `warn` |

```ruby
client = Typesafe::SDK::Client.new(
  timeout: 10, # Seconds per attempt, including connection setup and response body receipt.
  retry_policy: { max_retries: 2, backoff_initial_ms: 500 },
  log_level: :info, # :debug, :info, :warn, :error, or :off
  default_headers: { "X-My-App" => "support" },
)
```

`jev-latest` is a moving alias. For reproducible deployments, select an explicit model from
`client.models.list` and set `default_model:` or a per-call `model:`. See
[available models and aliases](https://docs.typesafe.ai/models).

## Retries and timeouts

By default, the SDK retries HTTP 408, 429, and 5xx responses, connection failures, and timeouts,
with up to two retries after the initial attempt. Backoff starts at 500 ms, doubles up to
5,000 ms, and uses up to 25% downward jitter. Server `Retry-After` and `retry-after-ms` delays
are honored up to 60,000 ms; larger delays fall back to backoff. From Ruby 0.6.0.1, blank
or malformed delay headers also fall back to backoff; an explicit zero remains valid.
A blank `retry-after-ms` still permits a valid `Retry-After` header to be used.

Each attempt receives a fresh timeout, so total call time can include several attempts and
backoff. Override settings per client or per call:

```ruby
client.system_one(
  state: "A refund request",
  questions: { billing: Typesafe::SDK.noul("Is this about billing?") },
  timeout: 30,
  retry_policy: { max_retries: 0 },
)
```

The full retry policy supports `max_retries`, `backoff_initial_ms`, `backoff_max_ms`,
`backoff_jitter`, `http_statuses`, `respect_retry_after`, `max_retry_after_ms`,
`api_connection_error`, and `api_timeout_error`. Overrides merge field by field.
Nil boolean flags inherit the existing setting; explicit `false` disables that behavior.

## Error handling

```ruby
begin
  client.system_one(
    state: "A refund request",
    questions: { billing: Typesafe::SDK.noul("Is this about billing?") },
  )
rescue Typesafe::SDK::RateLimitError => e
  warn "Rate limited; suggested retry delay: #{e.retry_after_ms.inspect}ms"
rescue Typesafe::SDK::APIError => e
  warn "API error #{e.status}; request ID: #{e.request_id}"
rescue Typesafe::SDK::APIConnectionError => e
  warn e.message
end
```

Errors reach your code after any configured retries. All SDK errors inherit from
`Typesafe::SDK::TypeSafeError`:

| Error | Meaning |
| --- | --- |
| `BadRequestError` | HTTP 400 |
| `AuthenticationError` | HTTP 401 |
| `PaymentRequiredError` | HTTP 402; added in 0.6.0.1 |
| `PermissionDeniedError` | HTTP 403 |
| `NotFoundError` | HTTP 404 |
| `ConflictError` | HTTP 409; added in 0.6.0.1 |
| `PayloadTooLargeError` | HTTP 413; added in 0.6.0.1 |
| `UnprocessableEntityError` | HTTP 422 |
| `RateLimitError` | HTTP 429; exposes `retry_after_ms` |
| `InternalServerError` | HTTP 5xx |
| `APIError` | Other non-2xx responses; exposes status, headers, body, and request ID |
| `APIConnectionError` | Connection or response-body delivery failure |
| `APITimeoutError` | Subclass of `APIConnectionError`; exposes `timeout_ms` |
| `APIUserAbortError` | Caller cancellation; never retried |

## Response metadata and additional fields

Added for Ruby **0.6.0.1**:

```ruby
result = client.system_one(
  state: "A refund request",
  questions: { billing: Typesafe::SDK.noul("Is this about billing?") },
  with_response: true,
)
puts result.data[:billing].noul
puts result.request_id
puts result.response.status
```

`client.models.list(with_response: true)` wraps the model cards the same way. The response
exposes case-insensitive `headers` and a parsed `body`.
`extra_body: { new_option: nil }` forwards additional JSON fields; named `state`, `questions`,
and `model` arguments take precedence. The API decides whether a field is supported.

## Cancellation

```ruby
signal = Typesafe::SDK::Signal.new
canceller = Thread.new { sleep 5; signal.cancel }
begin
  client.system_one(
    state: "A refund request",
    questions: { billing: Typesafe::SDK.noul("Is this about billing?") },
    signal: signal,
  )
rescue Typesafe::SDK::APIUserAbortError
  warn "Request canceled"
ensure
  canceller.kill.join
end
```

From Ruby 0.6.0.1, cancellation interrupts active requests and retry backoff, and cleans up
the request worker and socket before returning.

## Listing models

```ruby
client.models.list.each do |model|
  puts "#{model.name}: #{model.description} (#{model.release_date})"
end
```

## Logging and Rails

The default logger writes to `$stderr` with a `[typesafe-ai]` prefix. `info` includes request
summaries; `debug` adds redacted credential headers and request/response bodies. Bodies may
contain application data and are **not** redacted.

From Ruby 0.6.0.1, standard Ruby `Logger` and `Rails.logger` also accept debug details:

```ruby
# config/initializers/typesafe.rb; configure TYPESAFE_API_KEY through your secret store.
TYPESAFE = Typesafe::SDK::Client.new(logger: Rails.logger, log_level: :info)
```

Call `TYPESAFE.system_one(...)` from application code. In plain Ruby, use
`require "logger"` and pass `logger: Logger.new($stderr)`; add the `logger` gem to your
application if your Ruby version does not provide it by default.

## Coming from JavaScript

| JavaScript | Ruby |
| --- | --- |
| `new TypeSafeClient()` | `Typesafe::SDK::Client.new` |
| `systemOne(request, options)` | `system_one(state:, questions:, **options)` |
| `apiKey`, `baseURL`, `defaultModel` | `api_key:`, `base_url:`, `default_model:` |
| `timeout` in milliseconds | `timeout:` in seconds |
| `retry: { maxRetries: 0 }` | `retry_policy: { max_retries: 0 }` |
| `.withResponse()` | `with_response: true` (Ruby 0.6.0.1+) |
| `AbortController` | `Typesafe::SDK::Signal` |
| `answers.category` | `response[:category]` or `response.answers["category"]` |

Ruby calls are synchronous and return Ruby answer objects. They do not provide TypeScript
compile-time inference, Fetch streams, connection pooling, or automatic redirect following.
See [tested compatibility and intentional differences](docs/COMPATIBILITY.md).

## Development and contributing

```sh
bundle install
bundle exec rake # Tests and RuboCop; no API key or external API calls required.
```

Native transport tests bind loopback sockets. CI also builds and installs the packaged gem.
For an explicit live check, follow [live verification](docs/COMPATIBILITY.md#live-verification).
The [demo](examples/demo.rb) uses real API calls and can be run with
`bundle exec ruby examples/demo.rb` after configuring your key.

See [CONTRIBUTING.md](CONTRIBUTING.md), the [PR template](.github/PULL_REQUEST_TEMPLATE.md),
and the [release process](docs/RELEASING.md). Changes are reviewed and merged by the repository owner.

## Support and security

Use [issues](https://github.com/afurm/typesafe-sdk-ruby/issues) for Ruby client bugs and
[discussions](https://github.com/afurm/typesafe-sdk-ruby/discussions) for usage questions.
See [SUPPORT.md](SUPPORT.md) for API/account questions and useful report details.
Report vulnerabilities privately using [SECURITY.md](SECURITY.md).
All participation follows our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE), including attribution to the upstream TypeSafe JavaScript SDK.
