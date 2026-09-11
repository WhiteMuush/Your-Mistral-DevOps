# Contributing

Contributions are welcome: a new skill, an improvement to an existing guide, a fix to the system prompt.

## Before proposing

1. Read the [wiki](https://github.com/WhiteMuush/Your-Mistral-DevOps/wiki): it explains why the configuration is built in three layers. A rule placed in the wrong layer (`AGENTS.md` instead of the system prompt, or the other way round) will be refused with a pointer to the Architecture page
2. Every rule must come from an **observed problem**, not from an intuition. Describe the failure case in the pull request

## Testing your changes

Install into a throwaway directory, without touching your real configuration:

```bash
VIBE_HOME=/tmp/vibe-test bash install.sh
```

For a change to the system prompt or to a skill, attach a **differential test** to the pull request: a question whose answer differs depending on whether the rule is active, along with both observed answers. See the wiki page "Les skills" for the method.

## Conventions

- **Skills**: one directory per skill, `SKILL.md` inside, frontmatter carrying `name`, `description` and `user-invocable: true`. The description must list the trigger keywords
- **English**: all user-facing content is written in English
- **No em dash** anywhere in the text: use a comma, a colon or parentheses
- **Commits**: conventional format (`feat:`, `fix:`, `docs:`), subject of 50 characters at most, no `Co-Authored-By` line
- **Branches**: letters, digits, hyphens and slashes only (`feat/new-k8s-skill`)

## What will not be accepted

- Rules that weaken the protections of Vibe (auto-approve, automatic push, bypassing confirmations)
- Skills without a concrete method (collections of generalities such as "use best practices" help nobody)
- Content written in a language other than English in the user-facing prompts
