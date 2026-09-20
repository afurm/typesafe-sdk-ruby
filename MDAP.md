# TypeSafe SDK Ruby (Unofficial) — MDAP

**Master Development & Analysis Plan** for the unofficial Ruby SDK for the
[TypeSafe AI](https://typesafe.ai) API, ported from the official
[JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js) (v0.6.0).

> **Status:** This SDK is not affiliated with, endorsed by, or supported by TypeSafe AI.
> Official SDKs are JavaScript and Python only; this Ruby port is community-maintained.

---

## 1. Purpose and positioning

TypeSafe AI currently ships official SDKs for **Python** and **JavaScript** only. Ruby and
Ruby on Rails developers have no first-party option. This project provides an idiomatic,
well-tested Ruby gem (`typesafe-sdk`) that mirrors the JavaScript SDK's behavior so Ruby
applications — especially Rails services — can integrate with the TypeSafe API with the same
reliability characteristics: retries, timeouts, typed errors, and structured logging.

**Non-goals**

- No claims of official affiliation; the "unofficial" status is stated in the README, gem
  description, and repository topics.
- No feature surface beyond the official SDK. Parity is the goal, not invention.
- No Rails runtime dependency; the gem is framework-agnostic and works in any Ruby app.

## 2. Source analysis: typesafe-sdk-js v0.6.0

The JavaScript SDK was analyzed module by module. The table below maps every source module to
its Ruby counterpart and notes porting decisions.

| JS module | Responsibility | Ruby counterpart | Porting notes |
| --- | --- | --- | --- |
| `src/client.ts` | Client construction, config resolution, request/retry loop, header merging | `lib/typesafe/sdk/client.rb` | Constructor options become keywords; `fetch` becomes a pluggable `HTTP` adapter; `AbortSignal` becomes `Typesafe::SDK::Signal`; timeout in **seconds** (Ruby convention) instead of ms. |
| `src/types.ts` | Public types: questions, responses, request/config shapes | `lib/typesafe/sdk/types.rb` | Static types become runtime classes (`NoulResponse`, `ChoiceResponse`, `ScoreResponse`, `Usage`, `ModelCard`, `SystemOneResult`). Generic inference (`ResultFor<Q>`) has no Ruby equivalent; answers are accessed by name. |
| `src/questions.ts` | `noul`/`score`/`choice` builders and validation | `lib/typesafe/sdk/questions.rb` | Same validation rules: nonempty question set; score criteria must be a list of ≥ 2; choice criteria must be a map. |
| `src/errors.ts` | Error hierarchy and message extraction | `lib/typesafe/sdk/errors.rb` | Same subclass mapping (400/401/403/404/422/429/5xx), same message extraction (`error`, `error.message`, `message`, `detail`, validation arrays), same 200-char raw-body truncation. |
| `src/retry.ts` | Retry defaults, `Retry-After` parsing, backoff with jitter | `lib/typesafe/sdk/retry.rb` | Identical defaults (2 retries, 500 ms initial, 5 s cap, 0.25 jitter, statuses 408/429/5xx, 60 s retry-after cap). `retry-after-ms` preferred over `Retry-After`; HTTP-date supported. |
| `src/http.rb` (new) | — | `lib/typesafe/sdk/http.rb` | Replaces the global `fetch` with a `Net::HTTP` adapter returning a parsed `Response`. Swappable via `http:` for tests and custom transport. |
| `src/logging.ts` | Log levels, console logger, header redaction | `lib/typesafe/sdk/logging.rb` | Same levels (`debug`/`info`/`warn`/`error`/`off`, default `warn`), same redaction rules (key headers keep scheme + last 4 chars; cookies fully redacted). |
| `src/env.ts` | Environment variable fallbacks | `lib/typesafe/sdk/env.rb` | Same variables: `TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`, `TYPESAFE_DEFAULT_MODEL`, `TYPESAFE_LOG_LEVEL`; blank values ignored. |
| `src/api-promise.ts` | Promise subclass exposing the raw response | Not ported | Ruby has no promise chaining; `request` returns a parsed `Response` and `system_one` returns a `SystemOneResult` directly. Request ID is available on errors and responses. |
| `src/runtime.ts` | Runtime detection for the `X-TypeSafe-Runtime` header | Inline in `client.rb` | Reports `ruby/<RUBY_VERSION> (<platform>)`. |
| `src/resources/models.ts` | `GET /v1/models` | `lib/typesafe/sdk/resources/models.rb` | Same response-shape guard (`{ models: [...] }`). |
| `src/index.ts` | Public exports | `lib/typesafe-sdk.rb` | Top-level convenience builders (`Typesafe::SDK.noul`, `.score`, `.choice`). |

### API surface (parity contract)

- `POST /v1/systemone` — body: `{ state, questions, model }`; response: `{ model, answers, usage }`.
- `GET /v1/models` — response: `{ models: [ModelCard] }`.
- Headers: `Authorization: Bearer <key>`, `Accept: application/json`,
  `User-Agent: typesafe-sdk-ruby/<version>`, `X-TypeSafe-SDK`, `X-TypeSafe-Runtime`,
  `Content-Type: application/json` (when a body is present), `X-TypeSafe-Retry-Count` on retries.
- Request ID read from `x-typesafe-request-id`.

### Defaults preserved from the JS SDK

| Setting | Value |
| --- | --- |
| Base URL | `https://api.typesafe.ai` |
| Default model | `jev-latest` |
| Timeout per attempt | 10 s (JS: 10,000 ms) |
| Max retries | 2 |
| Backoff | 500 ms initial, ×2, 5 s cap, 25% jitter |
| Retryable statuses | 408, 429, 500–599 |
| Retry-after cap | 60 s |
| Log level | `warn` |

## 3. Repository layout

```
typesafe-sdk-ruby/
├── .github/
│   ├── ISSUE_TEMPLATE/          # bug report, feature request, question
│   └── workflows/               # ci.yml (matrix 3.1–3.4), release.yml (gem push)
├── docs/                        # reserved for guides
├── examples/
│   └── demo.rb                  # runnable demo mirroring the JS demo
├── lib/
│   ├── typesafe-sdk.rb          # entry point (require "typesafe-sdk")
│   └── typesafe/sdk/            # env, logging, retry, errors, questions, http,
│                                # types, client, resources/models, version
├── spec/                        # RSpec suite mirroring the JS test coverage
├── typesafe-sdk.gemspec
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE                      # MIT
├── MDAP.md                      # this document
└── README.md
```

## 4. Quality gates

- **Tests:** RSpec; 52 examples covering question builders and validation, retry policy and
  delay math, error mapping and message extraction, client construction and config precedence,
  request/retry behavior with a mocked HTTP adapter, header merging and auth protection,
  models resource, and version/gemspec consistency.
- **Lint:** RuboCop with `NewCops: enable`; the CI runs it on every matrix entry.
- **CI:** GitHub Actions matrix over Ruby 3.1–3.4; specs + RuboCop on push and PR.
- **Release:** tag-triggered workflow builds the gem, runs the full `rake` gate, pushes to
  RubyGems, and creates a GitHub release with generated notes.

## 5. Roadmap

1. **v0.6.x — parity hardening**
   - Integration test suite against a live API key (opt-in, mirroring `test:integration`).
   - YARD documentation coverage and a docs site or GitHub Pages.
   - Codecov or SimpleCov coverage reporting in CI.
2. **v0.7 — ergonomics**
   - Rails generator (`rails g typesafe:install`) for an initializer.
   - Async/concurrent request helper built on threads or `async`.
   - Streaming endpoints, if/when the API adds them.
3. **v1.0 — stability**
   - Frozen string literals and sorbet/rbs type signatures.
   - API review against accumulated feedback; semantic-versioning commitment.

## 6. Publishing checklist (public repo)

- [x] MIT `LICENSE` with contributor copyright line.
- [x] `README.md` with badges, quickstart, configuration, error handling, Rails usage.
- [x] `CHANGELOG.md` (Keep a Changelog format) and `CONTRIBUTING.md`.
- [x] CI and release workflows; issue templates.
- [x] `.gitignore` covering build artifacts and `Gemfile.lock` (library).
- [ ] Create the GitHub repository `typesafe-ai/typesafe-sdk-ruby` (or under a personal org)
      with description: *"Unofficial Ruby SDK for the TypeSafe AI API — typed questions,
      retries, and typed errors. Community port of typesafe-sdk-js."*
- [ ] Repository topics: `ruby`, `sdk`, `typesafe`, `typesafe-ai`, `api-client`,
      `unofficial`, `rails`, `gem`, `machine-learning`, `classification`.
- [ ] Enable GitHub Actions; add the `RUBYGEMS_API_KEY` secret for releases.
- [ ] Push `main`, tag `v0.6.0`, and `gem push` (or let the release workflow do it).
- [ ] Add a disclaimer note in the official JS repo discussions (optional, courteous).
