# Contributing

Thanks for your interest in contributing! This is a community-maintained, unofficial SDK for
the [TypeSafe AI](https://typesafe.ai) API, ported from the official
[JavaScript SDK](https://github.com/typesafe-ai/typesafe-sdk-js).

## Development setup

1. Install Ruby 3.1 or newer.
2. Clone the repository and install dependencies:

   ```sh
   bundle install
   ```

3. Run the test suite and linter:

   ```sh
   bundle exec rake        # specs + RuboCop
   bundle exec rspec       # specs only
   bundle exec rubocop     # lint only
   ```

## Guidelines

- Keep behavior aligned with the official JavaScript SDK. When in doubt, match its semantics
  (defaults, retry behavior, error mapping, header names).
- Add or update specs for any behavior change. All specs must pass.
- Run `bundle exec rubocop -a` before committing; the CI lints with the same config.
- Keep the gem dependency-free apart from `json`.
- Update `CHANGELOG.md` for user-facing changes.
- Keep `lib/typesafe/sdk/version.rb` and the version in `typesafe-sdk-ruby.gemspec` in sync; a spec
  enforces this.

## Pull requests

1. Fork the repository and create a feature branch from `main`.
2. Make your changes with focused commits.
3. Ensure `bundle exec rake` passes.
4. Open a pull request describing what changed and why.

## Reporting bugs

Open an [issue](https://github.com/afurm/typesafe-sdk-ruby/issues) with:

- The gem version and Ruby version (`ruby -v`).
- A minimal reproduction, ideally without your API key.
- Expected versus actual behavior.

Please do not include API keys or other secrets in issues.

## Code of conduct

Be kind and constructive. Maintainainers may remove comments or block accounts that are
disruptive.
