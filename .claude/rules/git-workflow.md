# Git Workflow Rules

## Commit Messages

Use conventional commits:
- `feat:` - New feature
- `fix:` - Bug fix
- `refactor:` - Code refactoring
- `perf:` - Performance improvement
- `docs:` - Documentation only
- `test:` - Adding/updating tests
- `chore:` - Maintenance tasks

Format:
```
feat(scope): brief description

Longer explanation if needed. Focus on WHY, not WHAT.

Refs #123
```

## Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `refactor/description` - Refactoring
- `perf/description` - Performance improvements
- `chore/description` - Maintenance

## PR Workflow

1. Create branch from `main`
2. Make focused, atomic commits
3. Run all validators before pushing
4. Create PR with description and test plan
5. Label the PR: exactly one `type` + at least one `area` (as `--label …` flags on the `gh pr create` call itself; `gh pr edit <n> --add-label …` if the PR is already open), never a `status` label. `bin/labels infer <changed paths>` gives the areas; the taxonomy is `.github/labels.yml`, the rules are `.github/LABELS.md`
6. Request review
7. Squash merge when approved

## Pre-Commit Checklist

Run before EVERY commit:
```bash
bundle exec rubocop              # Style
bundle exec rspec <relevant_specs>  # Tests
```

## Rules

- **NEVER** commit directly to `main`
- **NEVER** force push to shared branches
- **ALWAYS** run validators before committing
- **ALWAYS** write meaningful commit messages
- Keep commits small and focused
- One logical change per commit
- Labels are edited in `.github/labels.yml` and applied with `bin/labels sync`, never by hand in the GitHub UI. `bin/labels` and `.github/LABELS.md` are the zoolutions labels kit (canonical copy in docs-kit, see its LABELS_KIT.md): never edit them here — change docs-kit, then `script/labels-kit sync`
