# Upstream issue audit

Reviewed all **11 issues** returned by the official JavaScript repository's all-state issue
list on **2026-09-21**, including their comments. All were open at review time. The baseline
is `@typesafe-ai/sdk` **0.6.0**, commit `66880ccded6cb642dc1809620c2b108c33730214`.
Ruby changes below are included in **0.6.0.1 (unreleased)**.

This audit distinguishes client fixes from runtime differences and server feature requests.
It does not claim that the upstream issues are closed or that every requested API feature
is available. Valid supported requests continue to follow the JS wire format; reproducing
known JS bugs is not a compatibility goal.

## Disposition of every issue

| Upstream issue | Ruby disposition | Evidence or remaining limitation |
| --- | --- | --- |
| [#14: API key disclosure and empty keys](https://github.com/typesafe-ai/typesafe-sdk-js/issues/14) | Fixed locally | Validate explicit and environment keys at construction, trim outer spaces/tabs/line endings, reject empty/non-ASCII/control/embedded-whitespace values, and copy/freeze the key. Validation errors contain no key and make no request or retry. Header-construction failures also propagate without connection retries. |
| [#13: actionable HTTP error classes](https://github.com/typesafe-ai/typesafe-sdk-js/issues/13) | Implemented | HTTP 402, 409, and 413 map to `PaymentRequiredError`, `ConflictError`, and `PayloadTooLargeError`. Each remains an `APIError`, retains response metadata, and is not retried by default. |
| [#12: null score levels](https://github.com/typesafe-ai/typesafe-sdk-js/issues/12) | Fixed locally | Builders and raw hashes reject nil levels. Use an explicit empty string for an undescribed position; entries are never removed or renumbered. This workaround is reported accepted in the upstream issue, not independently verified against the live API here. |
| [#11: calibrated multi-label selection](https://github.com/typesafe-ai/typesafe-sdk-js/issues/11) | Requires upstream API/model support | Choice selects one option. Multiple noul questions are independent judgments, not a calibrated competitive multi-label substitute. The Ruby SDK does not invent such an endpoint or promise equivalent calibration. |
| [#10: cached or registered criteria](https://github.com/typesafe-ai/typesafe-sdk-js/issues/10) | Requires upstream API support | Reusing a Ruby question Hash still sends the criteria on each request and does not reduce billed tokens. There is no supported registration/cache API in the audited JS SDK. No synthetic `cached_tokens` field is exposed. |
| [#9: blank retry delay headers](https://github.com/typesafe-ai/typesafe-sdk-js/issues/9) | Fixed locally | Blank/whitespace-only delays fall back to configured backoff; blank milliseconds can fall through to valid seconds. Literal zero is still honored. Request-path tests verify the actual retry delay. |
| [#8: Node timer overflow](https://github.com/typesafe-ai/typesafe-sdk-js/issues/8) | Node-specific; Ruby equivalent tested | Ruby does not use Node timers. Real loopback requests with delayed responses succeed at and just above Node's 2,147,483,647 ms boundary, for both constructor and per-call settings. This is not a guarantee for every arbitrarily large OS timeout. |
| [#7: list the community Go SDK](https://github.com/typesafe-ai/typesafe-sdk-js/issues/7) | Upstream documentation request | No Ruby defect. Whether TypeSafe lists third-party clients is an upstream decision; this repository clearly identifies itself as unofficial. |
| [#6: API-invalid request shapes and limits](https://github.com/typesafe-ai/typesafe-sdk-js/issues/6) | Fixed locally | Require string/object/array state and reject nil; require noul instructions or a non-nil true/false description; enforce 2–10 score levels, 1–255 choice options, and nonempty question names. Empty state containers, single-option choice, and whitespace-only names remain allowed. |
| [#4: numeric choice label inference](https://github.com/typesafe-ai/typesafe-sdk-js/issues/4) | TypeScript-specific; Ruby equivalent tested | Ruby has no TypeScript `never` inference. Numeric labels serialize as JSON string keys and choice answers/probability keys remain strings. |
| [#2: handled cancellation crashes Node](https://github.com/typesafe-ai/typesafe-sdk-js/issues/2) | Different transport; Ruby equivalent tested | The Net::HTTP worker is cleaned up before cancellation returns. Separate processes with `Thread.abort_on_exception = true` catch `APIUserAbortError` and exit normally after cancellation during successful and error response bodies, for inference and model listing. Existing socket tests also exercise cancellation and worker cleanup. |

## Compatibility and migration

The local validation, blank-header handling, and added error subclasses intentionally differ
from JS 0.6.0. Previously accepted local inputs that are reported rejected by the API now raise
`TypeSafeError` earlier. In particular, replace `noul()` with an actual question or outcome
criteria, supply non-nil state, and replace nil score placeholders explicitly with descriptions
or empty strings. Do not drop score slots to pass validation, because their positions define
the scale. Nil choice descriptions remain supported.

Raw question hashes, including JSON-loaded hashes with string keys, receive the same checks
as builders. These targeted checks are not a complete copy of the server's evolving schema;
the API remains authoritative for other validation and model behavior.

New error subclasses retain the public `APIError` contract. Catching `APIError` continues to
work; code comparing exact classes may need updating. HTTP 402/409/413 are still excluded
from the default retry statuses.

For future server fields, `with_response: true` exposes the parsed response body, including
its raw `usage` object. This does not mean the server currently reports cache usage. Consult
upstream documentation before relying on newly introduced fields or sending `extra_body:`.

## Verification scope

- [Issue regressions](../spec/typesafe/sdk/upstream_issues_spec.rb): request validation,
  API key handling, retry scheduling, error mapping, and numeric labels using synthetic data.
- [Socket regressions](../spec/typesafe/sdk/http_spec.rb): actual Ruby transport behavior,
  including the Node timer boundary, cancellation, and slow/truncated bodies.
- [Subprocess cancellation](../spec/typesafe/sdk/cancellation_process_spec.rb): handled
  cancellation must not crash the caller process or leak an uncaught worker error.
- [JS baseline comparisons](../spec/typesafe/sdk/parity_spec.rb): fixtures generated by
  running the published JS package; known corrections are explicit in assertions and the
  fixture preserves the original JS output for those cases.

No live API key was available. Input constraints and reported server behavior above come from
upstream issue reports; tests prove Ruby's handling, not an independent live reproduction.
See [compatibility and live verification](COMPATIBILITY.md) for the opt-in smoke test.
