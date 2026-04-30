---
name: replicate-issue
description: |
  Replicate and validate a GitHub issue by spinning up the project's local app, analyzing the issue,
  and systematically testing all described symptoms using browser automation.
  Use when: User wants to reproduce a bug, validate a GitHub issue, confirm a reported problem,
  or investigate whether an issue is real before working on a fix.
  Triggers: "replicate issue", "reproduce issue", "validate issue", "confirm bug",
            "test issue", "can you reproduce", "try to replicate", "verify the bug".
  Capability: Detects the project's dev server config, switches to main, pulls latest, starts the app,
  reads the GitHub issue, then uses agent-browser to systematically test every symptom and produce a findings report.
  NOT for: Fixing issues (only reproduces and reports), general UI testing.
argument-hint: "[issue-number]"
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, WebFetch, Agent
---

# Replicate GitHub Issue

Systematically reproduce and validate a GitHub issue against the live app.
The goal: determine whether the reported behavior is real, identify exact reproduction steps,
discover any related issues, and provide actionable fix recommendations.

**Issue number**: `$ARGUMENTS`

If `$ARGUMENTS` is empty, ask the user for the issue number before proceeding.

---

## Phase 0: Detect & Prepare Environment

### 0.1 Locate Project Root and Branch

```bash
# Find project root
PROJECT_ROOT=$(git rev-parse --show-toplevel)
cd "$PROJECT_ROOT"

# Stash any local changes
git stash 2>/dev/null || true

# Switch to main and pull latest
git checkout main
git pull origin main

echo "On branch: $(git branch --show-current)"
echo "Latest commit: $(git log --oneline -1)"
```

### 0.2 Detect Dev Server Command

Read `package.json` to find the dev script (priority order):

```bash
DEV_CMD="${DEV_PIPELINE_START_CMD:-}"
if [ -z "$DEV_CMD" ]; then
  for SCRIPT in dev start "start:dev" serve; do
    if jq -e ".scripts.\"$SCRIPT\"" package.json >/dev/null 2>&1; then
      DEV_CMD="$SCRIPT"
      break
    fi
  done
fi

if [ -z "$DEV_CMD" ]; then
  echo "ERROR: No dev script found in package.json. Set DEV_PIPELINE_START_CMD env var or add a 'dev' script."
  exit 1
fi

echo "Dev command: $DEV_CMD"
```

### 0.3 Detect Ports

Check env overrides, then config files, then standard defaults:

```bash
# Backend port: env override → look for PORT in scripts/.env → default 3000
BACKEND_PORT="${BACKEND_PORT:-}"
if [ -z "$BACKEND_PORT" ]; then
  BACKEND_PORT=$(grep -hE "PORT=[0-9]+" package.json .env 2>/dev/null | grep -oE "PORT=[0-9]+" | head -1 | cut -d= -f2)
  BACKEND_PORT="${BACKEND_PORT:-3000}"
fi

# Frontend port: env override → framework heuristic → default
FRONTEND_PORT="${FRONTEND_PORT:-}"
if [ -z "$FRONTEND_PORT" ]; then
  if [ -f vite.config.ts ] || [ -f vite.config.js ] || [ -f vite.config.mjs ]; then
    FRONTEND_PORT=5173
  elif [ -f next.config.js ] || [ -f next.config.mjs ] || [ -f next.config.ts ]; then
    FRONTEND_PORT=3000
  else
    FRONTEND_PORT=3000
  fi
fi

echo "Backend port: $BACKEND_PORT, Frontend port: $FRONTEND_PORT"
```

### 0.4 Free Up Ports

```bash
fuser -k "$BACKEND_PORT/tcp" 2>/dev/null || true
[ "$FRONTEND_PORT" != "$BACKEND_PORT" ] && fuser -k "$FRONTEND_PORT/tcp" 2>/dev/null || true
sleep 2

! fuser "$BACKEND_PORT/tcp" 2>/dev/null && echo "Port $BACKEND_PORT is free" || echo "WARNING: Port $BACKEND_PORT still in use"
```

### 0.5 Start the App

Detect the package manager, then run the detected dev script:

```bash
PKG_MGR_FILE=$(ls bun.lockb pnpm-lock.yaml yarn.lock package-lock.json 2>/dev/null | head -1)
case "$PKG_MGR_FILE" in
  bun.lockb)        RUNNER="bun run" ;;
  pnpm-lock.yaml)   RUNNER="pnpm" ;;
  yarn.lock)        RUNNER="yarn" ;;
  package-lock.json|"") RUNNER="npm run" ;;
esac

$RUNNER "$DEV_CMD" &
DEV_PID=$!
sleep 8

# Verify backend is responding
curl -s "http://localhost:$BACKEND_PORT/" > /dev/null && echo "Backend responding on $BACKEND_PORT" || echo "WARNING: Backend not responding on $BACKEND_PORT"

# Verify frontend is responding
curl -s "http://localhost:$FRONTEND_PORT" > /dev/null && echo "Frontend responding on $FRONTEND_PORT" || echo "Note: Frontend port may have shifted (Vite auto-increments). Check the dev output."
```

**Note**: If detection fails or your project uses non-standard ports/startup, override via env vars before invoking the skill: `BACKEND_PORT`, `FRONTEND_PORT`, `DEV_PIPELINE_START_CMD`.

---

## Phase 1: Analyze the Issue

### 1.1 Read the GitHub Issue

```bash
gh issue view $ARGUMENTS --json title,body,labels,comments,state
```

Parse the issue carefully. Extract:
- **Title and summary**: What is the reported problem?
- **Reproduction steps**: What specific actions trigger the bug?
- **Expected behavior**: What should happen?
- **Actual behavior**: What happens instead?
- **Environment details**: Any specific conditions (browser, OS, timing)?
- **Labels and priority**: How severe is this?
- **Comments**: Any additional context, workarounds, or related issues?

### 1.2 Build a Test Plan

Based on the issue content, create a checklist of specific things to test.
For each symptom described in the issue, define:
1. The exact user journey to reproduce it
2. What to look for (expected vs actual)
3. Screenshots to capture as evidence

---

## Phase 2: Reproduce with Browser Automation

Use the `agent-browser` CLI (NOT Playwright) for all browser interactions.

### Core Workflow

```bash
# 1. Navigate to the page
agent-browser open "http://localhost:$FRONTEND_PORT"

# 2. Get interactive elements
agent-browser snapshot -i

# 3. Interact using refs from the snapshot
agent-browser click @e1
agent-browser fill @e2 "text"

# 4. Re-snapshot after navigation or DOM changes
agent-browser snapshot -i

# 5. Take screenshots at every significant point
agent-browser screenshot /tmp/issue-$ARGUMENTS-{step-name}.png
```

### Testing Guidelines

- **Take screenshots liberally** — before and after each action, save to `/tmp/issue-$ARGUMENTS-*.png`
- **Read every screenshot** — use the Read tool to visually inspect each screenshot and verify what you see
- **Test the happy path first** — confirm the feature works under normal conditions before testing the bug
- **Follow the exact reproduction steps** from the issue — don't shortcut
- **Test variations** — try the same flow with slight differences (different data, different timing, page refresh)
- **Test adjacent flows** — if the issue is about workflow X, also check workflows Y and Z for similar problems
- **Use curl for API verification** — cross-reference UI state with direct API calls to confirm data accuracy
- **Check after page refresh** — many SSE/real-time bugs only manifest after navigation or refresh
- **Wait for async operations** — use `agent-browser wait` commands for network-dependent operations

### Triggering API Calls (if the issue involves backend behavior)

If the issue requires API testing alongside UI reproduction, use `curl` against the running backend:

```bash
curl -s -X POST "http://localhost:$BACKEND_PORT/<endpoint>" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'
```

Refer to the project's API docs or routes definition for endpoint details.

---

## Phase 3: Document Findings

For each symptom in the issue, record:

| Symptom | Reproduced? | Evidence | Notes |
|---------|-------------|----------|-------|
| {symptom from issue} | YES / NO / PARTIAL | Screenshot path | {details} |

### Severity Classification

- **Confirmed (Reproducible)**: The exact bug described in the issue was reproduced
- **Partially Confirmed**: The symptom appears but under different conditions than described
- **Not Reproduced**: Could not reproduce despite following the described steps
- **Related Issue Found**: A different but related problem was discovered during testing

---

## Phase 4: Investigate Root Cause (if reproduced)

If the issue was reproduced, do a targeted codebase analysis:

1. **Identify the affected components** — which files/hooks/components are involved?
2. **Read the relevant source code** — understand the current implementation
3. **Trace the data flow** — where does the data come from? SSE? REST? React Query? useState?
4. **Identify the root cause** — what specifically causes the observed behavior?
5. **Check for similar patterns** — are other components vulnerable to the same issue?

---

## Phase 5: Recommendations

Provide **multiple fix options** with trade-offs:

### Option Format

For each recommendation:

```markdown
### Option N: {Short title}

**Approach**: {1-2 sentence description}

**Changes required**:
- {file}: {what changes}
- {file}: {what changes}

**Pros**:
- {benefit}

**Cons**:
- {drawback}

**Complexity**: Low / Medium / High
**Risk**: Low / Medium / High
```

Provide at least 2-3 options ranging from quick fix to comprehensive solution.

---

## Phase 6: Cleanup

```bash
# Close the browser
agent-browser close

# Stop the dev server (optional — leave running if user wants to continue testing)
# kill $DEV_PID 2>/dev/null
# fuser -k "$BACKEND_PORT/tcp" 2>/dev/null
# fuser -k "$FRONTEND_PORT/tcp" 2>/dev/null
```

---

## Phase 7: Summary Report

Present a final summary to the user:

```markdown
# Issue #$ARGUMENTS Replication Report

## Issue: {title}
**Status**: Reproduced / Not Reproduced / Partially Reproduced
**Tested on**: main @ {commit hash}

## Reproduction Summary
{2-3 sentences describing what was tested and the outcome}

## Findings
{Detailed findings with screenshot references}

## Root Cause
{If identified — what causes the bug and why}

## Related Issues Discovered
{Any additional problems found during testing}

## Recommendations
{Summary of fix options with recommended approach}
```

---

## Execution Notes

- Always use `agent-browser` (Vercel Agent Browser CLI), NOT Playwright
- Load the `/agent-browser` skill if you need a command reference
- Take screenshots at EVERY significant test point — these are your evidence
- Read screenshots with the Read tool to visually verify what the UI shows
- If reproduction requires long-running operations, be patient — wait for workflows to complete
- Cross-reference browser state with API responses (`curl`) to distinguish UI bugs from backend bugs
- If the issue cannot be reproduced, document what you tried and suggest possible reasons
- Close the browser when finished: `agent-browser close`
