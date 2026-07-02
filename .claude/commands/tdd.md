---
description: "Use when implementing any feature or fixing any bug -- enforces RED-GREEN-REFACTOR: write failing test first, implement minimum code to pass, then refactor."
model: sonnet
---

# TDD Command

Enforce test-driven development methodology with RED -> GREEN -> REFACTOR cycle.

## The TDD Cycle

```text
RED -> GREEN -> REFACTOR -> REPEAT

RED:      Write a failing test (test MUST fail first)
GREEN:    Write MINIMAL code to pass (nothing more)
REFACTOR: Improve code while keeping tests green
REPEAT:   Next feature/scenario
```

## When to Use

- Implementing new features
- Adding new lock types or conflict strategies
- Fixing bugs (write test that reproduces bug FIRST)
- Refactoring existing code
- Modifying Lua scripts
- Changing middleware behavior

## Workflow

### Step 1: Define Interface (SCAFFOLD)

```ruby
# lib/sidekiq_unique_jobs/lock/new_lock_type.rb
module SidekiqUniqueJobs
  class Lock
    class NewLockType < BaseLock
      def lock
        # TODO: Implementation
        raise NotImplementedError
      end

      def execute
        # TODO: Implementation
        raise NotImplementedError
      end
    end
  end
end
```

### Step 2: Write Failing Tests (RED)

```ruby
# spec/sidekiq_unique_jobs/lock/new_lock_type_spec.rb
RSpec.describe SidekiqUniqueJobs::Lock::NewLockType do
  let(:item) { { "class" => "MyWorker", "args" => [1] } }

  describe "#lock" do
    context "when no existing lock" do
      it "acquires the lock" do
        expect(subject.lock).to be_truthy
      end
    end

    context "when lock already exists" do
      before { create_existing_lock }

      it "fails to acquire" do
        expect(subject.lock).to be_falsey
      end
    end
  end
end
```

### Step 3: Run Tests - Verify FAIL

```bash
bundle exec rspec spec/sidekiq_unique_jobs/lock/new_lock_type_spec.rb

FAIL - NotImplementedError
```

**Tests MUST fail before implementing.** This confirms:
- Tests are actually running
- Tests are testing the right thing
- Implementation doesn't already exist

### Step 4: Implement Minimal Code (GREEN)

Write the minimum code to make the test pass.

### Step 5: Run Tests - Verify PASS

```bash
bundle exec rspec spec/sidekiq_unique_jobs/lock/new_lock_type_spec.rb

N examples, 0 failures
```

### Step 6: Refactor (IMPROVE)

Improve code while keeping tests green:
- Extract constants
- Improve naming
- Reduce duplication
- Ensure Lua scripts are atomic

### Step 7: Run Full Suite

```bash
bundle exec rspec
```

## Coverage Requirements

| Code Type | Minimum Coverage |
|-----------|------------------|
| All code | 80% |
| Lock types | 100% |
| Lua scripts | 100% |
| Middleware | 100% |
| Conflict strategies | 100% |
| Orphan reapers | 100% |

## Test Types to Include

### Unit Tests (Lock types, Locksmith, Config)
- Happy path scenarios
- Edge cases (empty args, nil values, expired locks)
- Error conditions
- Race conditions (concurrent lock attempts)
- Lock lifecycle (acquire -> execute -> release)

### Integration Tests (Middleware)
- Client middleware enqueue prevention
- Server middleware execution locking
- Full job lifecycle with uniqueness
- Conflict strategy behavior

### Lua Script Tests
- Atomic operations verified
- Key expiration behavior
- Multi-key operations

## Best Practices

**DO:**
- Write the test FIRST, before any implementation
- Run tests and verify they FAIL before implementing
- Write MINIMAL code to make tests pass
- Refactor only after tests are green
- Test with `Sidekiq::Testing.disable!` for real Redis behavior
- Test lock expiration with TTL

**DON'T:**
- Write implementation before tests
- Skip running tests after each change
- Write too much code at once
- Ignore failing tests
- Test implementation details (test behavior)
- Mock Redis when testing lock behavior

## Checklist

- [ ] Tests written BEFORE implementation
- [ ] Tests fail initially (RED phase verified)
- [ ] Minimal code written to pass (GREEN)
- [ ] Code refactored with tests still passing
- [ ] Coverage meets requirements (80%+)
- [ ] All edge cases covered
- [ ] Backwards compatibility maintained
