#!/bin/bash
# log-submission.sh - Claude Code UserPromptSubmit hook for Talkie feedback
#
# Logs user submissions to Talkie's unified feedback log for STT correction learning.
#
# Installation:
#   mkdir -p ~/.talkie/hooks
#   cp log-submission.sh ~/.talkie/hooks/
#   chmod +x ~/.talkie/hooks/log-submission.sh
#
# Configure in ~/.claude/settings.json:
#   {
#     "hooks": {
#       "UserPromptSubmit": [
#         {
#           "type": "command",
#           "command": "~/.talkie/hooks/log-submission.sh"
#         }
#       ]
#     }
#   }

FEEDBACK_LOG="$HOME/.config/talkie/feedback.jsonl"

# Ensure directory exists
mkdir -p "$(dirname "$FEEDBACK_LOG")"

# Read JSON from stdin, transform to unified format
jq -c '{
  ts: (now * 1000 | floor),
  type: "submit",
  text: .prompt,
  session_id: .session_id
}' >> "$FEEDBACK_LOG"
