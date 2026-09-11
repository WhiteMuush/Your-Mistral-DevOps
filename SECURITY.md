# Security

## Scope

This repository holds no application code: an install script (`install.sh`), configuration files and prompts. The main risks are therefore:

- **`install.sh`**: it writes into `$VIBE_HOME` (`~/.vibe` by default) and edits `config.toml`. It downloads nothing, runs nothing else, and never asks for elevated privileges. Read it before running it, it is 50 lines long
- **The prompts and skills**: they steer the behaviour of an AI agent which, in turn, runs commands. No rule in this repository weakens the protections of Vibe (tool permissions stay the ones in your own `config.toml`). The system prompt explicitly forbids unrequested git pushes

## What this repository never does

- Collect or transmit data
- Touch API keys or secrets (`.env` patterns stay protected by the user's Vibe configuration)
- Disable the tool confirmations of Vibe

## Reporting a vulnerability

If you find a security problem, for instance a prompt rule that could push the agent towards dangerous behaviour:

1. Preferably: [GitHub Security Advisories](https://github.com/WhiteMuush/Your-Mistral-DevOps/security/advisories/new) (private report)
2. Otherwise: open an issue describing the context, without detailing the exploitation if it is sensitive

There is no bug bounty programme: this is a personal project, but reports are read and handled.
