# Releasing sidekiq-unique-jobs

Releases are fully automated via GitHub Actions with supply chain security built in.

## Security features

| Feature | Description |
|---------|-------------|
| **Trusted publishing (OIDC)** | No long-lived API keys. RubyGems.org verifies the GitHub Actions identity via OpenID Connect. |
| **Sigstore attestation** | Every gem is signed with a keyless Sigstore signature, logged in a public transparency log. |
| **SHA-256 + SHA-512 checksums** | Checksum files attached to every GitHub release for independent verification. |
| **Tag-version gate** | CI refuses to publish if the git tag doesn't match `SidekiqUniqueJobs::VERSION`. |
| **Gem content verification** | CI unpacks the gem and checks for unwanted files (`.git*`, the gemspec, `spec/`, `test/`) before publishing; the gemspec's file whitelist keeps everything else (rake files, `myapp/`) out. |
| **MFA required** | `rubygems_mfa_required` is set in the gemspec. Manual pushes require MFA. |
| **Environment protection** | The `rubygems` GitHub environment can require approvals before publish. |

## How to release

```bash
bin/release list                 # last releases + what each bump would give
bin/release --dry-run            # version, changes since the last tag, downstream blockers
bin/release                      # patch bump (or `minor` / `major`)
bin/release 9.0.0.alpha3         # explicit version; alpha/beta/rc/pre = pre-release
bin/release 9.0.0.alpha3 --force # delete + re-create an existing tag/release
```

`bin/release` checks you're on a clean, up-to-date `main`, warns when
`version.rb` and the newest tag disagree, confirms, and hands off to
`rake release[X.Y.Z]` (`rakelib/release.rake`). The task bumps
`lib/sidekiq_unique_jobs/version.rb` and the `sidekiq-unique-jobs` pin in the
tracked `docs/` and `myapp/` lockfiles, verifies `gem build --strict`, commits,
pushes `main`, and runs `gh release create`, which triggers the CI pipeline.
`bin/release`, `rakelib/release.rake` and everything in `release.yml` except its
`test` job are the zoolutions release kit, shared verbatim with the other gems
(canonical copy and upgrade steps: docs-kit's `RELEASE_KIT.md`). Don't edit
them here.

1. **test** — runs rubocop + rspec against Redis
2. **build** — verifies tag/version match, builds gem with `--strict`, verifies contents, generates checksums
3. **publish-rubygems** — verifies checksums, obtains OIDC credentials, signs with Sigstore, pushes to RubyGems
4. **upload-release-assets** — attaches `.gem` + checksums + Sigstore bundle to the release

## Initial setup (one-time)

### 1. Configure trusted publishing on RubyGems.org

1. Go to https://rubygems.org/gems/sidekiq-unique-jobs
2. Navigate to **Trusted publishers** in the sidebar
3. Click **Create** and fill in:
   - Repository owner: `mhenrixon`
   - Repository name: `sidekiq-unique-jobs`
   - Workflow filename: `release.yml`
   - Environment: `rubygems`

### 2. Create the GitHub environment

1. Go to the repo **Settings → Environments**
2. Create an environment named `rubygems`
3. (Optional) Add protection rules:
   - Required reviewers for extra safety
   - Limit to the `main` branch

### 3. Remove old secrets

If `RUBYGEMS_API_KEY` exists in repo secrets, it can be removed — trusted publishing replaces it entirely.

## Verifying a release

### Checksums

Download the `.sha256` or `.sha512` file from the GitHub release and verify:

```bash
# Download release assets
gh release download vX.Y.Z --repo zoolutions/sidekiq-unique-jobs

# Verify checksums
sha256sum -c sidekiq-unique-jobs-X.Y.Z.gem.sha256
sha512sum -c sidekiq-unique-jobs-X.Y.Z.gem.sha512
```

### Sigstore attestation

```bash
gem exec sigstore-cli verify-bundle \
  --bundle sidekiq-unique-jobs-X.Y.Z.gem.sigstore.json \
  --certificate-identity "https://github.com/zoolutions/sidekiq-unique-jobs/.github/workflows/release.yml@refs/tags/vX.Y.Z" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  sidekiq-unique-jobs-X.Y.Z.gem
```

### RubyGems.org

Attestations are also visible on the gem's version page at https://rubygems.org/gems/sidekiq-unique-jobs.

## Local build verification

To verify gem contents locally without publishing:

```bash
bundle exec rake build
```

This builds the gem with `--strict` mode and lists all packaged files.
