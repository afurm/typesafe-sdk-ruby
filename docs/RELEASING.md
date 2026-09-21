# Releasing

Only the repository owner merges pull requests and initiates releases. Opening or merging
a pull request does not publish a gem. Publication starts when the owner pushes a version tag.

## Versions

`Typesafe::SDK::UPSTREAM_VERSION` records the official JS compatibility target.
`Typesafe::SDK::VERSION` is the Ruby package version and is the single source for the gemspec.

- A new upstream port uses its exact three-part version, for example `0.7.0`.
- Ruby-only corrections use a fourth numeric component, for example `0.6.0.1` and `0.6.0.2`.
  These still target JS `0.6.0`; they do not imply an upstream `0.6.1` release.
- Published versions and tags must not be replaced or reused. RubyGems accepts numeric
  fourth-component versions as stable releases.

Before a new upstream port, compare the tagged source and tests, update the compatibility
document and generated fixtures, and run the suite. Version equality alone is not evidence
of compatibility.

## Owner checklist

1. Review and merge the release pull request after all CI matrix jobs pass.
2. Run the opt-in live smoke test described in [COMPATIBILITY.md](COMPATIBILITY.md).
3. Set the changelog release date and update the README release-status notice in a reviewed
   pull request before tagging.
4. On the merged main commit, run `bundle exec rake`, `ruby script/check_release.rb`, and
   `gem build typesafe-sdk-ruby.gemspec --strict`.
5. Create and push the matching annotated tag, for example `v0.6.0.1`.
6. Verify the Release workflow, RubyGems version, GitHub release, and attached gem artifact.

The workflow rejects non-owner runs, tags that differ from the gem version, commits outside
main's history, and upstream versions that do not match the official tagged package.
It reruns tests and lint before publishing with the repository's `RUBYGEMS_API_KEY` secret.
Keep that credential restricted to this gem. Required branch checks remain in force.

If RubyGems publication succeeds but GitHub release creation fails, verify the published
artifact before recovering the GitHub release; do not delete the tag or republish the version.
