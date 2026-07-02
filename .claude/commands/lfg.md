---
description: "Executes full autonomous engineering workflow with verification. Use when implementing complete features, tackling GitHub issues, or running end-to-end development cycles."
model: opus
argument-hint: "GitHub issue number/URL or feature description"
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(bundle exec:*), Bash(git:*), Read, Write, Edit, Glob, Grep, Agent
---

# LFG - Full Autonomous Workflow

Execute a complete engineering workflow with verification at each phase.

## Phase 0: Branch Setup

**BEFORE any other work, prepare the git branch:**

1. Check the current branch: `git branch --show-current`
2. If NOT on `main`, switch: `git checkout main`
3. Pull latest: `git pull origin main`
4. Create feature branch: `git checkout -b issue-{number}-{brief-description}` (or `feature/{description}` if no issue number)

---

## Phase 1: Understand

### Step 1: Gather Requirements

If `$ARGUMENTS` is a GitHub issue number or URL:

```bash
gh issue view <number> --json title,body,labels,assignees,comments
```

If `$ARGUMENTS` is a description, use it directly.

### Step 2: Define Acceptance Criteria

**MANDATORY:** Write explicit acceptance criteria:

- **GIVEN** [context/setup]
- **WHEN** [action taken]
- **THEN** [expected outcome]

You MUST NOT proceed until you can articulate these clearly.

### Step 3: Comprehension Gate

Before proceeding, you must:

1. State the problem/feature in one sentence
2. Explain WHY this is needed (business context)
3. List what will change from the user's perspective
4. Identify edge cases not explicitly mentioned
5. Explain the data flow or code path involved

If you cannot complete ALL five items, investigate further.

### Step 4: Create Task List

Create a TaskCreate todo list with specific implementation steps.

---

## Phase 2: Explore

1. Find related files (Glob/Grep or Explore agent)
2. Read existing patterns in similar features
3. Understand dependencies and integration points
4. Check existing test coverage
5. Review relevant Lua scripts in `lib/sidekiq_unique_jobs/lua/`
6. Check lock type implementations in `lib/sidekiq_unique_jobs/lock/`

---

## Phase 3: Plan

1. List files to modify with specific changes
2. List new files to create with purpose
3. Identify Lua script changes needed
4. Plan test coverage (TDD: tests FIRST)
5. Update task list with implementation steps
6. Consider backwards compatibility with existing lock types

---

## Phase 4: Implement (TDD)

For each logical unit:

### 4.1: Write Failing Test First

Create a test that demonstrates the expected behavior. Run it to confirm it FAILS:

```bash
bundle exec rspec <spec_file>
```

### 4.2: Implement Minimum Code

Write the MINIMUM code to make the test pass. Follow project patterns:

| Never Do | Always Do |
|----------|-----------|
| Direct Redis calls | Use Lua scripts for atomicity |
| Skip lock cleanup | Always handle lock lifecycle |
| Ignore Sidekiq version compat | Check `Sidekiq::VERSION` when needed |
| Hardcode Redis key names | Use `SidekiqUniqueJobs::Key` |
| Skip conflict strategies | Implement `on_conflict` handling |

### 4.3: Refactor

Once green, refactor while keeping tests passing.

### 4.4: Validate

```bash
bundle exec rubocop <changed_files>
```

### 4.5: Repeat

Move to next logical unit. Mark task items complete.

---

## Phase 5: Deep Root Cause Analysis (Bug Fixes Only)

**If this is a bug fix, apply deep investigation before implementing:**

### Trace the Data Lifecycle

For the lock/job/value causing the issue:
- Where and when was the lock created? By what middleware?
- What state transitions does the lock go through?
- What ASSUMPTIONS does the code make at the failure point?
- Which assumption was violated, and WHY?

### Use Git History

```bash
git log --oneline -20 <file>
git blame <file>
```

- When was the code written? What was the original intent?
- Has something ELSE changed that invalidated the original assumptions?

### Map All Callers

Don't just look at the method that failed:
- Use Grep to find all call sites
- Different contexts (client middleware vs server middleware vs reaper)?
- Does the error only happen in ONE context? Why?

### Five Whys

Keep asking WHY until you reach a meaningful fix point:

1. Error: X happened -> Why?
2. Because Y -> Why was Y in that state?
3. Because Z -> Why wasn't Z prevented?
4. Because no check existed -> Why not?
5. **THIS** is where the fix belongs

### Fix Location Principle

The best fix is usually NOT where the error is raised:
- Nil reference in locksmith -> fix in middleware that should provide non-nil
- Lock not found -> fix in code that deleted prematurely
- Race condition -> Lua script-level locking
- Invalid lock state -> fix the lock lifecycle management

**Ask: "Where is the EARLIEST point I could prevent this error?" Fix there.**

### Unacceptable Superficial Fixes -- DO NOT DO THESE

- `rescue nil` without understanding why the exception occurs
- `&.` to silence nil errors without investigating why nil occurs
- `if object.present?` guards without understanding why missing
- `return if lock.nil?` to silently skip processing
- Wrapping everything in `begin/rescue` to swallow errors

**These HIDE bugs. The root cause continues causing issues elsewhere.**

---

## Phase 6: Verify

**ALL of these must pass before committing:**

```bash
bundle exec rubocop              # Style
bundle exec rspec <relevant_specs>  # Tests
bundle exec reek                 # Code smells (if applicable)
```

### Solution Verification

Re-read the original requirements and verify:
- "If I were the requester, would I consider this fully resolved?"
- "Have I addressed the ROOT CAUSE, not just the symptom?"
- "Do my tests prove the issue is ACTUALLY fixed, not just suppressed?"
- "Does this maintain backwards compatibility?"

---

## Phase 7: Commit & PR

### Commit

```bash
git add <specific_files>
git commit -m "$(cat <<'EOF'
feat(scope): brief description

## Summary
[What changed and why]

## Test Coverage
- spec 1: validates requirement X
- spec 2: validates edge case Y

## Verification
- [x] bundle exec rubocop passes
- [x] bundle exec rspec passes
EOF
)"
```

### Push & PR

```bash
git push -u origin $(git branch --show-current)

gh pr create --title "feat(scope): brief description" --body "$(cat <<'EOF'
## Summary
- Key change 1
- Key change 2

Closes #<issue_number>

## Test plan
- [ ] Scenario 1
- [ ] Scenario 2
EOF
)"
```

---

## Verification Checklist

- [ ] All acceptance criteria met
- [ ] Tests written BEFORE implementation
- [ ] `bundle exec rubocop` passes
- [ ] `bundle exec rspec` passes
- [ ] Backwards compatibility maintained
- [ ] Lua scripts are atomic
- [ ] PR created with description

---

## Handoff

When complete:
- All phases executed
- Verification passed
- PR created and linked

Now, execute this workflow for the provided issue or feature.
