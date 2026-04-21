#!/bin/bash

# Kai Neovim Enhancement Script with Intelligent Action Detection
# Usage: kai-neovim.sh <context_file> <prompt>

CONTEXT_FILE="$1"
PROMPT="$2"

# Check if claude CLI is available (we use it to communicate with Kai)
if ! command -v claude &>/dev/null; then
  echo "Error: Claude CLI not found. Please install it first."
  exit 1
fi

# Read the CLAUDE.md files for additional context (project-specific rules for Kai)
GLOBAL_CLAUDE_MD=""
LOCAL_CLAUDE_MD=""

if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  GLOBAL_CLAUDE_MD=$(cat "$HOME/.claude/CLAUDE.md")
fi

# Find the nearest CLAUDE.md in the project
CURRENT_DIR=$(pwd)
while [ "$CURRENT_DIR" != "/" ]; do
  if [ -f "$CURRENT_DIR/CLAUDE.md" ]; then
    LOCAL_CLAUDE_MD=$(cat "$CURRENT_DIR/CLAUDE.md")
    break
  fi
  CURRENT_DIR=$(dirname "$CURRENT_DIR")
done

# Regular text enhancement request - let Kai determine the action
FULL_PROMPT="You are Kai, an AI assistant integrated into Neovim. 

CRITICAL CONTEXT FROM CLAUDE.md FILES (FOLLOW THESE RULES EXACTLY):
==================================================
GLOBAL CLAUDE.md:
$GLOBAL_CLAUDE_MD

PROJECT CLAUDE.md:
$LOCAL_CLAUDE_MD
==================================================

CURRENT EDITING CONTEXT:
$(cat "$CONTEXT_FILE")

CRITICAL: INTELLIGENT ACTION DETECTION
You must analyze the user's instruction to determine what they want:

1. If they say things like \"replace with\", \"change to\", \"rewrite as\", \"make this\", \"convert to\" → REPLACE the selected text
2. If they say things like \"write something like this\", \"create a note about\", \"add after\", \"insert\" → INSERT new content (don't replace)
3. If they say things like \"improve\", \"enhance\", \"fix\", \"correct\" → REPLACE with improved version
4. If they say things like \"explain this\", \"what is this\", \"analyze\", \"tell me about\", \"show me\", \"list\", \"count\", \"find\" → DISPLAY information (don't modify file)

IMPORTANT: When working with selected text, focus on that specific text within the context of the entire buffer. When working without selection, make targeted changes at the cursor location.

RESPONSE FORMAT:
You must start your response with ONE of these action markers on its own line:
[ACTION:REPLACE]
[ACTION:INSERT_AFTER]
[ACTION:INSERT_BEFORE]
[ACTION:DISPLAY]

Then on the next line, provide the content:
- For REPLACE/INSERT actions: provide ONLY the text to insert (no explanations)
- For DISPLAY actions: provide the analysis/information to show the user

IMPORTANT INSTRUCTIONS:
- First line must be the action marker
- Follow ALL formatting rules from CLAUDE.md
- Maintain the code style and conventions of the file
- Consider the context when generating content
- You are Kai, the AI assistant integrated into Neovim

User instruction: $PROMPT"

# Get the response with action marker
RESPONSE=$(echo "$FULL_PROMPT" | claude -p) # Using claude CLI to communicate with Kai

# Output the response
echo "$RESPONSE"

# Exit with the command's exit code
exit $?
