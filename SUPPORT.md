# Support

This is an unofficial community Ruby SDK. The repository maintainer handles Ruby client
behavior; TypeSafe AI handles its API, models, accounts, and billing.

- **Ruby bugs:** open a [bug report](https://github.com/afurm/typesafe-sdk-ruby/issues/new?template=bug_report.md).
  Include the gem/Ruby versions, a small reproduction, expected and actual behavior, and
  the request ID when available. Mention whether you used the default HTTP adapter.
- **Usage questions:** use [GitHub Discussions](https://github.com/afurm/typesafe-sdk-ruby/discussions).
- **API behavior and account questions:** consult the [official docs](https://docs.typesafe.ai/),
  [API console](https://console.typesafe.ai/), or contact options on [TypeSafe AI](https://typesafe.ai/).
- **Security vulnerabilities:** use the private reporting route in [SECURITY.md](SECURITY.md).

Do not include API keys, cookies, or private customer data. Debug logging masks known
credential headers but does not sanitize state, questions, response bodies, or custom headers.
Review logs before sharing them.

For parity reports, include the exact official JavaScript SDK version and the smallest
input that behaves differently. Consult [COMPATIBILITY.md](docs/COMPATIBILITY.md) for
intentional Ruby differences and the verified upstream release.
