#!/bin/bash
# PostToolUse hook: validate label application from triage-agent.
# Only runs when invoked from inside triage-agent's context (self-filter on agent_type).
# Emits soft warnings to stderr but never blocks (exit 0 always).
#
# Validates:
#   - Exactly one type label (bug, feature, feature-request, docs, chore, question, security, performance, breaking)
#   - Exactly one effort label (effort/low, effort/medium, effort/high)
#   - Exactly one priority label (P0, P1, P2, P3)
#   - At least one area label

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
if [ "$AGENT_TYPE" != "triage-agent" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if ! echo "$COMMAND" | grep -qE 'gh issue edit.*--add-label'; then
  exit 0
fi

# Extract label values — handles --add-label "x", --add-label=x, --add-label x
LABELS=$(echo "$COMMAND" | grep -oE -- '--add-label[= ]"[^"]*"|--add-label[= ][^ ]+' \
  | sed -e 's/--add-label[= ]//' -e 's/^"//' -e 's/"$//')

if [ -z "$LABELS" ]; then
  exit 0
fi

TYPE_RE='^(bug|feature|feature-request|docs|chore|question|security|performance|breaking)$'
EFFORT_RE='^effort/(low|medium|high)$'
PRIORITY_RE='^P[0-3]$'

TYPE_COUNT=$(echo "$LABELS" | grep -cE "$TYPE_RE")
EFFORT_COUNT=$(echo "$LABELS" | grep -cE "$EFFORT_RE")
PRIORITY_COUNT=$(echo "$LABELS" | grep -cE "$PRIORITY_RE")
AREA_COUNT=$(echo "$LABELS" | grep -cvE "$TYPE_RE|$EFFORT_RE|$PRIORITY_RE")

WARNINGS=""
[ "$TYPE_COUNT" -ne 1 ] && WARNINGS="$WARNINGS  - Expected exactly 1 type label, got $TYPE_COUNT\n"
[ "$EFFORT_COUNT" -ne 1 ] && WARNINGS="$WARNINGS  - Expected exactly 1 effort label, got $EFFORT_COUNT\n"
[ "$PRIORITY_COUNT" -ne 1 ] && WARNINGS="$WARNINGS  - Expected exactly 1 priority label, got $PRIORITY_COUNT\n"
[ "$AREA_COUNT" -lt 1 ] && WARNINGS="$WARNINGS  - Expected at least 1 area label, got 0\n"

if [ -n "$WARNINGS" ]; then
  printf "Triage label validation warnings:\n%b" "$WARNINGS" >&2
fi

exit 0
