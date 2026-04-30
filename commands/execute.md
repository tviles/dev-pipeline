---
description: Execute an implementation plan file
argument-hint: <path-to-plan.md>
---

# Execute: Implement a Plan

## Objective

Read and execute every task in the plan file: **$ARGUMENTS**

Implement all tasks faithfully, following the project's conventions, and report results.

---

## Step 1: Read the Entire Plan

Read the plan file at `$ARGUMENTS` from start to finish before writing a single line of code.
Understand:

- All tasks and their dependencies
- Affected packages and files
- Architecture notes and prohibited patterns
- The validation steps at the end

Do NOT start implementing until you have the full picture.

---

## Step 2: Verify Current State

Check the working tree is clean before starting:

```bash
git status
```

If there are uncommitted changes unrelated to this plan, flag them before proceeding.

Check the current branch:

```bash
git branch --show-current
```

---

## Step 3: Execute Tasks in Dependency Order

Work through each task in the plan sequentially (respecting `Depends on:` ordering).

### For each task:

1. **Locate** the target site. If the plan provides a code-fragment anchor, prefer it over
   the line number — rebases and new commits shift line numbers between plan-write and
   plan-execute time.
2. **Read** the target file(s) before modifying — never edit blindly.
3. **Implement** the change using the Edit or Write tools.
4. **Verify** the change compiles after touching TypeScript files:
   ```bash
   bun run type-check 2>&1 | tail -20
   ```
   Fix type errors immediately — do not accumulate them.
5. **Format immediately** if the task touched `.ts` / `.tsx` / `.json` / `.md` files:
   ```bash
   bun run format
   ```
   Prettier's wrap/line-break heuristics often diverge from hand-written formatting.
   Running `format` inside the task loop (not just before `validate`) saves a full
   validation round-trip.
6. **Grep for consumers** if the task changed a function signature, return type, or
   predicate's behavior. Type-check catches direct callers, but not tests that assert on
   *derived* values (e.g. a test asserting on a specific fallback value produced by the
   old signature).

   ```bash
   # Scan for both the symbol name AND any literal values its old behavior produced
   grep -rn "symbolName\|'--specific-flag'" packages/ --include="*.ts" --include="*.tsx"
   ```

   For every match not already touched by this task or a downstream task in the plan,
   decide whether it needs updating. Surface a missed consumer *now* — don't wait for
   red tests to find it.

### Project conventions to follow

Read `CLAUDE.md` and inspect surrounding code to learn the project's conventions before editing. Common categories to check:

**Imports:**
- Use `import type` for type-only imports
- Prefer specific named imports over `import *` for project modules
- Match the existing style in nearby files

**Functions:**
- Match existing return-type style (explicit vs inferred)
- Avoid `any` without a justification comment

**Logging:**
- Use the project's logger (check existing imports — pino, winston, console, custom)
- Match existing log structure and event-name conventions

**Error handling:**
- Never swallow errors silently
- Re-throw with context, or classify for user-facing handling
- Match the project's error-shape conventions

**Git operations:**
- Avoid destructive commands (`git clean -fd`, `git reset --hard`) unless the task specifically requires them
- Prefer the project's git utilities if they exist

**Package boundaries:**
- Respect any documented import rules (typically: downstream modules should not import from upstream)
- Inspect existing import patterns to infer the convention

**Testing:**
- Match the project's test framework and structure
- Run tests via the scripts defined in `package.json`

**Testing (if adding tests):**
- Check which test batch the new file belongs to in the package's `package.json`
- `mock.module()` is permanent in Bun — place new test files to avoid polluting other files
- Use `spyOn()` for modules other test files also use directly (not `mock.module()`)

---

## Step 4: Run Incremental Validation

After completing all tasks in a package, run validation for that package:

```bash
# Type checking across all packages
bun run type-check

# Lint (zero warnings policy)
bun run lint

# Format check
bun run format:check

# Tests (per-package isolation — do NOT run from repo root directly)
bun run test
```

Fix any failures before proceeding to the next package group.

---

## Step 5: Run Full Validation

After all tasks are complete, run the full validation suite:

```bash
bun run validate
```

This runs: `type-check && lint --max-warnings 0 && format:check && test`

All four must pass. If any fail, fix them before reporting completion.

---

## Step 6: Output Report

Provide a structured completion report:

```
## Execution Report: {Plan Name}

### Tasks Completed
- [x] Task 1: {description} — {files changed}
- [x] Task 2: {description} — {files changed}
...

### Files Created
- `packages/{pkg}/src/{file}.ts` — {purpose}

### Files Modified
- `packages/{pkg}/src/{file}.ts` — {what changed}

### Validation Results
- type-check: PASS / FAIL
- lint: PASS / FAIL (N warnings)
- format:check: PASS / FAIL
- tests: PASS / FAIL (N passed, N failed)
- Full `bun run validate`: PASS / FAIL

### Manual Verification
{Any curl commands or UI steps to manually verify the feature works.}

### Notes
{Any deviations from the plan, unexpected findings, or follow-up work needed.}
```
