#!/usr/bin/env bash
set -euo pipefail

# Installs the Vibe configuration (AGENTS.md + skills + system prompt) into the user's Vibe directory.
# Honours $VIBE_HOME when defined, otherwise ~/.vibe.

VIBE_HOME="${VIBE_HOME:-$HOME/.vibe}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/vibe" && pwd)"

echo "Target: $VIBE_HOME"
mkdir -p "$VIBE_HOME/skills" "$VIBE_HOME/prompts"

# Back up any existing AGENTS.md before overwriting it
if [ -f "$VIBE_HOME/AGENTS.md" ]; then
  BACKUP="$VIBE_HOME/AGENTS.md.bak.$(date +%Y%m%d%H%M%S)"
  cp "$VIBE_HOME/AGENTS.md" "$BACKUP"
  echo "Existing AGENTS.md backed up: $BACKUP"
fi

cp "$SRC/AGENTS.md" "$VIBE_HOME/AGENTS.md"
echo "AGENTS.md installed."

# Copy each skill (merge, existing skills are left in place)
cp -r "$SRC/skills/." "$VIBE_HOME/skills/"
echo "Skills installed:"
find "$SRC/skills" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort | sed 's/^/  - /'

# Custom system prompt (base: built-in Vibe 2.19.1 prompt + style, skills and git rules)
cp "$SRC/prompts/cli-caveman.md" "$VIBE_HOME/prompts/cli-caveman.md"
echo "System prompt cli-caveman installed."

# Enable the system prompt in config.toml when present
CONFIG="$VIBE_HOME/config.toml"
if [ -f "$CONFIG" ]; then
  if grep -q '^system_prompt_id' "$CONFIG"; then
    if ! grep -q '^system_prompt_id = "cli-caveman"' "$CONFIG"; then
      sed -i.bak 's/^system_prompt_id = .*/system_prompt_id = "cli-caveman"/' "$CONFIG"
      echo "config.toml: system_prompt_id switched to cli-caveman (backup: config.toml.bak)."
    else
      echo "config.toml: system_prompt_id already set to cli-caveman."
    fi
  else
    printf '\nsystem_prompt_id = "cli-caveman"\n' >> "$CONFIG"
    echo "config.toml: system_prompt_id = cli-caveman added."
  fi
else
  echo "WARNING: $CONFIG not found. Add manually: system_prompt_id = \"cli-caveman\""
fi

echo
echo "Done. Restart Vibe to reload the configuration."
echo "Skills are invoked with /name (for example /init, /terraform-guide)."
