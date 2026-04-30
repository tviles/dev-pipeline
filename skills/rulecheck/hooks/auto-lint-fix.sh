#!/bin/bash
# PostToolUse hook: auto-fix lint issues after Edit/Write from rulecheck-agent.
# Only runs when invoked from inside rulecheck-agent's context (self-filter on agent_type).
#
# Input: JSON on stdin with hook event context
# Output: exit 0 always (failures don't block the agent)

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
if [ "$AGENT_TYPE" != "rulecheck-agent" ]; then
  exit 0
fi

bun run lint:fix --quiet 2>/dev/null || true
exit 0
