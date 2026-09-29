# Agent Orchestration Rules

## Available Agents

| Agent | Model | Purpose | When to Use |
|-------|-------|---------|-------------|
| Explore | `model: haiku` | Codebase exploration | Finding files, understanding patterns |
| Plan | `model: sonnet` | Implementation planning | Complex features, architectural decisions |
| general-purpose | `model: sonnet` | Multi-step tasks | Research, complex searches |

Every agent spawned names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL` in `.claude/settings.json`).

## Immediate Agent Usage

Use agents PROACTIVELY without waiting for user prompt:

1. **Complex feature requests** -> Use Plan agent first
2. **Codebase exploration** -> Use Explore agent
3. **Multi-file searches** -> Use Explore agent (not direct Glob/Grep)
4. **Architectural decisions** -> Use Plan agent

## Parallel Execution

**ALWAYS** use parallel Task execution for independent operations:

```markdown
# GOOD: Parallel execution
Launch multiple agents simultaneously:
1. Agent 1: Explore lock implementations
2. Agent 2: Check Lua script patterns
3. Agent 3: Review test coverage

# BAD: Sequential when unnecessary
First explore, wait, then check Lua, wait, then review...
```

## When to Use Explore Agent

Use the Explore agent (subagent_type=Explore, `model: haiku`) instead of direct Glob/Grep when:
- Open-ended codebase exploration
- Searching for patterns across lock types, middleware, and Lua scripts
- Answering questions about codebase structure
- Finding related implementations across Ruby and Lua

## When NOT to Use Agents

Use direct tools when:
- Reading a specific known file path
- Simple pattern match in known location
- Single-file edits
- Running specific commands
