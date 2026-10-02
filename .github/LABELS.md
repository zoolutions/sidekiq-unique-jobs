# Labels

`.github/labels.yml` is the source of truth for this repository's labels.
GitHub is made to match it with:

```bash
bin/labels validate         # check the manifest (offline)
bin/labels sync --dry-run   # show the create/update/delete plan
bin/labels sync             # create and update
bin/labels sync --delete    # also remove labels the manifest dropped
```

Never add or edit a label in the GitHub UI: the next sync reverts it, and the
reason for it is nowhere in the history. Change `labels.yml` in a pull request,
then sync.

## The rule

**Every pull request carries exactly one `type` label and at least one `area`
label. Never a `status` label.** A pull request that closes an issue carries the
issue's `type` and `area` labels; otherwise they are inferred from the change.

Issues carry the same `type` + `area` labels, plus `status` labels that come and
go as the issue moves.

## Groups

| Group | How many | Meaning |
|---|---|---|
| type | exactly 1 | what kind of work this is |
| area | 1 or more | which part of the code it touches |
| status | 0 or more, issues only | where the issue is in its lifecycle |
| source | 0 or more | where the item came from, when that was not a person |
| community | 0 or more | GitHub's contributor-facing defaults |
| legacy | — | kept for history; never applied to new items |

### type

| Label | Use for | Conventional commit |
|---|---|---|
| `bug` | a defect fix | `fix:` |
| `enhancement` | a new feature or capability | `feat:` |
| `performance` | faster or leaner, same behaviour | `perf:` |
| `tech-debt` | refactoring or cleanup | `refactor:` |
| `security` | a vulnerability, hardening, an authorization fix | `fix:` |
| `documentation` | docs only (README, guides, the docs site's content) | `docs:` |
| `dependencies` | dependency bumps | `chore(deps):` / `build:` |
| `chore` | CI, tooling, configuration, tests with no behaviour change | `chore:` / `ci:` / `test:` |

When a change is two things at once, label the one a reviewer most needs to
know: `security` beats `bug`, and `bug` beats `tech-debt`.

### area

The areas are this repository's own and live in `labels.yml` with a description
each. Three are shared by every repository on the labels kit:

- `devops`: CI, the release kit, Docker, deploys and infrastructure
- `dx`: agent commands and rules, generators, local tooling
- `docs-site`: the documentation site under `docs/`

### status

`plan`: has a `/plan` body (Context, Decision, Steps, Gates) and is ready for
`/lfg`. `epic`, `blocker` and `needs-info` mean what they say. A repository may
add its own (for example `flaky-test`).

## Inferring the area from a diff

`labels.yml` carries a `paths:` map of glob → area label. The commands use it so
labelling is deterministic rather than a judgment call per pull request:

```bash
bin/labels infer $(git diff --name-only origin/main...HEAD)
```

Globs are matched with `File.fnmatch` and `File::FNM_PATHNAME | File::FNM_EXTGLOB`,
so write a recursive glob as `**/*`. An area with no reliable path signal is
applied by judgment. When `infer` prints nothing, pick the closest area by hand.
Never open a pull request with zero area labels.

## Labelling a pull request

```bash
gh pr create --label <type> --label <area> [--label <area>…] …
gh pr edit <n> --add-label <type> --add-label <area>   # after the fact
```

`gh pr create` fails on a label that does not exist on GitHub. If one in the
manifest is missing, run `bin/labels sync`. Don't create it with
`gh label create` unless you are also adding it to `labels.yml`.

## Retiring a label

Deleting a label strips it from every issue and pull request without a trace,
so re-labelling comes first:

```bash
bin/labels migrate <old> <new…>   # add <new…>, remove <old>, on open AND closed items
bin/labels sync --delete
```

`sync --delete` refuses to delete a label that is still on any issue or pull
request, open or closed, and names the items. A label with history worth
keeping but no future stays in the manifest under the `legacy` group instead. Labels matching the manifest's `ignore:` globs are
owned by some automation and are never touched.

## The kit

`bin/labels` and this file are the zoolutions labels kit: byte-identical in
every repository, with the canonical copy in docs-kit (`LABELS_KIT.md`). Change
them there, then run `script/labels-kit sync`. Never edit them in place.
