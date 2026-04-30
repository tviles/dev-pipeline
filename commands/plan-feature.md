---
description: Create a comprehensive implementation plan for a feature
argument-hint: <feature-name-or-description>
---

# Plan Feature: Comprehensive Implementation Planning

## Objective

Produce a detailed, actionable implementation plan for: **$ARGUMENTS**

The plan will be saved to `.claude/dev-pipeline/plans/{kebab-case-name}.md` and is designed to be
consumed by the `/execute` command.

---

## Phase 1: Feature Understanding

Restate the feature request in your own words. Identify:

1. **Problem being solved** — What user pain point or capability gap does this address?
2. **Success criteria** — What does "done" look like? How will we verify it works?
3. **Scope boundaries** — What is explicitly in scope vs. out of scope?
4. **Package impact** — Which of the 8 packages are affected? (`paths`, `git`, `isolation`,
   `workflows`, `core`, `adapters`, `server`, `web`)
5. **Interface changes** — Does this touch `IPlatformAdapter`, `IAgentProvider`,
   `IDatabase`, or `IWorkflowStore`? New interfaces needed?

---

## Phase 2: Codebase Intelligence

Use subagents to perform targeted codebase research in parallel. Spawn separate subagents for:

**Subagent A — Affected package deep-dive:**
Read all relevant source files in the affected packages. Map the current data flow.
Identify every file that will need to change.

**Subagent B — Interface and type contracts:**
Read `packages/core/src/types/` and relevant `index.ts` exports. Understand what interfaces
exist and how they're consumed across packages.

**Subagent C — Test patterns:**
Find existing test files similar to the area of change:

```bash
find packages/ -name "*.test.ts" | head -30
```

Read 2-3 representative test files to understand mocking patterns, assertion style, and
`mock.module()` isolation requirements per package.

**Subagent D — Related prior work:**
```bash
git log --oneline --all | head -20
```
Read recent commits touching relevant files to understand change patterns.

Synthesize findings: current state, gaps, constraints.

---

## Phase 3: External Research (if needed)

If the feature involves external APIs, new libraries, or unfamiliar patterns, use web search
to research:

- Relevant SDK documentation
- Known gotchas or version incompatibilities
- Community patterns for the problem domain

Document any specific findings that affect the implementation approach.

---

## Phase 4: Strategic Thinking

Before writing tasks, reason through:

**Architecture decisions:**
- Where does this logic belong? Apply SRP — keep each module focused on one concern.
- Does this require a new package, or extends an existing one?
- What's the dependency direction? Never create circular deps (paths ← git ← isolation/workflows ← core ← adapters ← server).

**Interface design:**
- Prefer extending existing narrow interfaces over creating fat ones.
- New interface methods only if they have a concrete current caller.
- Avoid adding methods to `IPlatformAdapter` or `IAgentProvider` unless essential.

**Test isolation strategy:**
- `mock.module()` is process-global and permanent in Bun — plan test file placement carefully.
- If adding tests to packages with split test batches (core, workflows, adapters, isolation),
  determine which batch the new test belongs to.

**ESLint compliance:**
- All new functions need explicit return types.
- No `any` without justification.
- Zero-warning policy enforced in CI.

**Rollback plan:**
- What is the blast radius if this goes wrong?
- Are changes reversible without a DB migration?

---

## Phase 4.5: Hidden-Dependency Scan

Before finalizing the task list, scan for hidden dependencies on any function signatures,
predicates, or return types the plan will change. Type-checking catches direct callers, but
tests often assert on *derived* behavior — they break silently when a signature tightens
because the old assertion was only passing due to a placeholder value (e.g. `undefined`)
propagating through downstream logic.

**When to run:** Any task that changes a function's return type, narrows a parameter, or
alters a predicate's return value (e.g. `string | undefined → string`, a boolean flipping
under the same input, an enum gaining a variant).

**Scan steps:**

1. List every symbol whose signature or return shape the plan changes.
2. For each symbol, grep across `packages/**/*.test.ts` — both the symbol name AND the
   literal values the symbol previously produced (e.g. an old `undefined` fallback, an
   asserted string like `'--no-env-file'`, a specific object shape):

   ```bash
   grep -rn "symbolName\|'--specific-flag'" packages/ --include="*.test.ts"
   ```

3. For each match not already covered by a planned task, decide: update it, remove it, or
   flag it as "no change required" with a brief reason documented in the plan.
4. Add any affected test files to the task list before finalizing.

**Why this matters (lesson from past execution):** A planner that reads only the describe
blocks it expects to change will miss incidental assertions in neighboring tests. The grep
is cheap; the surprise at execute time (red tests on an otherwise-clean diff) is not.
When a test's assertion depends on a resolver returning a specific placeholder value in a
fallback path, it's brittle — it passes not because the behavior is correct, but because
the broken behavior happens to produce the asserted value. Surface these at plan time.

---

## Phase 5: Plan Generation

Generate the implementation plan at `.claude/dev-pipeline/plans/{kebab-case-feature-name}.md`:

```markdown
# Plan: {Feature Name}

## Overview
{1-2 sentence summary of what this implements and why.}

## Success Criteria
- [ ] {Verifiable criterion 1}
- [ ] {Verifiable criterion 2}
- [ ] Passes `bun run validate` (type-check + lint + format + tests)

## Affected Areas
- `{feature-name}` — {what changes}

## Architecture Notes
{Key decisions, tradeoffs, interface changes.}

## Implementation Tasks

### Task 1: {descriptive name}
**File:** `packages/{package}/src/{file}.ts`
**Type:** Create | Modify | Delete
**Description:** {What this task does and why.}
**Depends on:** {Task N, or "none"}

For **Modify** tasks, include an **Anchor** block with both a line number AND a quoted
code fragment (1-3 lines) that uniquely identifies the location:

```markdown
**Anchor:** around line 123 — search for the fragment below if line drifts

\`\`\`typescript
// 1-3 lines of existing code that uniquely identify the location
\`\`\`
```

Line numbers drift between plan-write and plan-execute if the branch receives new
commits. The code fragment is a content-addressed anchor that survives rebases — the
executor should prefer it when the line number no longer matches.

### Task 2: ...

## Validation Steps
1. `bun run type-check` — must pass with zero errors
2. `bun run lint` — must pass with zero warnings
3. `bun run format:check` — must pass
4. `bun run test` — must pass (run via `bun --filter '*' test` for isolation)
5. Manual test: {specific curl command or UI steps to verify the feature}

## Rollback Notes
{How to safely revert if needed.}
```

### Task Ordering Rules
- Order by dependency (blocked tasks come after their dependencies).
- Group by package when possible to minimize context switching.
- Database schema changes (if any) come first.
- Type/interface definitions before implementations.
- Tests after implementations.
- Frontend after backend API is stable.

### Prohibited Patterns (flag in plan if you see a risk)
- Generic `import *` from project modules — use named imports
- `any` type without justification comment
- Circular package dependencies
- `git clean -fd` in any script or test
- `bun test` from repo root (use `bun run test` or `bun --filter '*' test`)

---

## Output

1. Save the plan file to `.claude/dev-pipeline/plans/{kebab-case-name}.md`
2. Print the plan to the conversation
3. Summarize: number of tasks, affected packages, estimated complexity (low/medium/high),
   and any risks or open questions that need resolution before execution.
