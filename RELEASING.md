# Releasing sidekiq-unique-jobs

Releases are fully automated via GitHub Actions with supply chain security built in.

## Security features

| Feature | Description |
|---------|-------------|
| **Trusted publishing (OIDC)** | No long-lived API keys. RubyGems.org verifies the GitHub Actions identity via OpenID Connect. |
| **Sigstore attestation** | Every gem is signed with a keyless Sigstore signature, logged in a public transparency log. |
| **SHA-256 + SHA-512 checksums** | Checksum files attached to every GitHub release for independent verification. |
| **Tag-version gate** | CI refuses to publish if the git tag doesn't match `SidekiqUniqueJobs::VERSION`. |
| **Gem content verification** | CI unpacks the gem and checks for unwanted files (specs, rake files, etc.) before publishing. |
| **MFA required** | `rubygems_mfa_required` is set in the gemspec. Manual pushes require MFA. |
| **Environment protection** | The `rubygems` GitHub environment can require approvals before publish. |

## How to release

```bash
# Stable release
rake release[1.2.3]

# Pre-release
rake release[1.2.3.alpha1]

# Release current version as pre-release (no version bump)
rake release[pre]
```

The rake task handles everything locally (version bump, commit, push) then runs
`gh release create` which triggers the CI pipeline:

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
