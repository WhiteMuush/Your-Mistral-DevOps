---
name: dev-conventions
description: Writes code, commits and branches that match the conventions of the project. Automatically reads CONTRIBUTING.md, AGENTS.md, .editorconfig and the linter configuration before writing, then mirrors the existing style. Triggers before any code is written or modified, before a commit, before creating a branch, or on "commit", "branch", "contributing", "convention", "code style", "linter".
user-invocable: true
---

# Dev conventions: code, commits, branches

Goal: never write at random. Always detect the rules of the project first, then comply with them.

## Step 1, detect the conventions (BEFORE writing)

Read, when present, in this order, the most specific winning:

1. `CONTRIBUTING.md` (also `CONTRIBUTING` without extension, `docs/CONTRIBUTING.md`)
2. `AGENTS.md`, `CLAUDE.md`, `.cursorrules` (agent rules of the repository)
3. `.editorconfig` (indentation, line endings, charset)
4. Formatter and linter configuration for the stack:
   - JS and TS: `.prettierrc`, `.eslintrc*`, `biome.json`
   - Python: `pyproject.toml` (ruff, black), `setup.cfg`, `.flake8`
   - Go: `gofmt` is implicit. Ruby: `.rubocop.yml`
5. Package manager scripts (`package.json` scripts, `Makefile`, `justfile`) to learn the lint, format and test commands.

When a `CONTRIBUTING.md` exists, its rules override generic habits.

## Step 2, mirror the existing code

Before writing into a file, look at the neighbouring files and imitate:

- Indentation, quotes, semicolons.
- Naming style (camelCase, snake_case, PascalCase).
- Import organisation.
- Comment density, do not comment more than the surrounding code.

Rules:

- Do not introduce a new style without a reason.
- No comment except for a WHY that is not obvious.
- Run the formatter and linter of the project when available, never a personal format.
- Never the em dash, in code, comments or documentation. Use a comma, a colon or parentheses.

## Step 3, commits

1. Read the existing style: `git log --oneline -20`.
2. When the repository uses Conventional Commits (`feat:`, `fix:`, `chore:` and so on), follow it. Otherwise copy the dominant style of the log.
3. Subject in the imperative, short (around 50 characters), with no full stop.
4. A body only when the WHY is not obvious. Explain the why, not the what.
5. Strictly forbidden:
   - Never a `Co-Authored-By:` line.
   - Never the em dash.

Example:

```
feat(auth): add refresh token

Sessions expired after an hour and forced a re-login. A silent refresh avoids that.
```

## Step 4, branches

1. Read the existing names: `git branch -a`.
2. Follow the dominant pattern. When there is none, default to `type/short-description` in kebab-case.
   - `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`.
   - For example: `feat/refresh-token`, `fix/login-timeout`.
3. No spaces, no capitals, no accents.
4. When `CONTRIBUTING.md` imposes a branch format, it wins.

## Reminder

Never commit or push unless the user asks. On a default branch (main or master), create a branch first.
