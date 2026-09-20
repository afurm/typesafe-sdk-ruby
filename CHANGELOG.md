# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-09-20

Initial release. A community port of the official
[TypeSafe JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js) v0.6.0.

Published as the `typesafe-sdk-ruby` gem (the `typesafe-sdk` name is already taken on
RubyGems by an unrelated project).

### Added

- `Typesafe::SDK::Client` with `system_one` and a `models` resource.
- Question builders: `noul`, `score`, and `choice`, with request validation.
- Typed answer objects: `NoulResponse`, `ChoiceResponse`, `ScoreResponse`, plus `Usage`
  and `ModelCard`.
- Automatic retries for HTTP 408/429/5xx, connection failures, and timeouts, with capped
  exponential backoff, jitter, and `Retry-After` / `retry-after-ms` support.
- Per-attempt timeouts and cooperative cancellation via `Typesafe::SDK::Signal`.
- Typed error hierarchy: `TypeSafeError`, `APIError` subclasses per HTTP status,
  `APIConnectionError`, `APITimeoutError`, and `APIUserAbortError`.
- Structured logging with level filtering and credential-header redaction.
- Configuration from `TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`, `TYPESAFE_DEFAULT_MODEL`,
  and `TYPESAFE_LOG_LEVEL`, with explicit options taking precedence.
- Pluggable HTTP adapter for custom transport or testing.
