---
name: Bug report
about: Create a report to help us improve
labels: bug
---

**Describe the bug**
A clear and concise description of what the bug is.

**Expected behavior**
A clear and concise description of what you expected to happen.

**Current behavior**
What happens instead of the expected behavior?

**Worker class**

```ruby
class MyWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: :undefault
  def perform(args); end

  def self.lock_args(args)
    # the way you consider unique arguments
  end
end
```

**Additional context**
Add any other context about the problem here.
