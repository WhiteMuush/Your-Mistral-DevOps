<img src="https://cdn.simpleicons.org/mistralai/FF6200" width="80" align="left" alt="" />

### Your Mistral DevOps

**A ready-to-use, shareable Mistral Vibe configuration for Dev and Ops work.**

<br clear="all" />

An `AGENTS.md` holding the global rules, 11 DevOps and development skills, and a custom system prompt that forces skills to be read, git to be used systematically and answers to stay short. One command to install it.

> The **[wiki](https://github.com/WhiteMuush/Your-Mistral-DevOps/wiki)** explains how this is built and why: the three-layer architecture, the system prompt in detail, and the real problems met along the way with their diagnosis.

## Quick install

```bash
git clone https://github.com/WhiteMuush/Your-Mistral-DevOps.git
cd Your-Mistral-DevOps
bash install.sh
```

Then restart Vibe. That is all.

The installer copies into `~/.vibe/`, or into `$VIBE_HOME` when that variable is set. An existing `AGENTS.md` is backed up as `.bak.<date>` before being overwritten. Skills are merged, so the ones already in place are kept.

## Contents

```
vibe/
├── AGENTS.md          # global rules, always-on compressed style, skill routing table
├── prompts/
│   └── cli-caveman.md # custom system prompt (see the section below)
└── skills/
    ├── init/                     # /init: scans a repository, writes a project AGENTS.md
    ├── dev-conventions/          # code, commits and branches matching the project
    ├── terraform-guide/
    ├── helm-chart-builder/
    ├── ansible-playbook-builder/
    ├── docker-swarm-guide/
    ├── argocd-guide/
    ├── prometheus-grafana-setup/
    ├── azure-cloud-advisor/
    ├── github-actions-expert/
    └── gitlab-ci-guide/
```

## Usage

Every skill is callable as a slash command: `/init`, `/terraform-guide`, `/dev-conventions`, and so on.

On a new repository, run `/init` once: it detects the stack, reads the relevant skills, and writes an `AGENTS.md` at the project root that Vibe will read again at every session.

## The custom system prompt

`AGENTS.md` alone is not enough: Vibe wraps it in a "may or may not be relevant" warning, and the model drifts over long sessions. The system prompt is a stronger channel.

`vibe/prompts/cli-caveman.md` is the built-in Vibe prompt, copied as is from version 2.19.1, plus four sections appended at the end:

1. **Compressed style**: short answers, never copying back a file that was just read, readability rules (one idea per line, bold, lists)
2. **Mandatory skills**: read the `SKILL.md` of the domain before acting, even when the prompt already gives the structure. The skill overrides training knowledge
3. **Systematic git**: `git init` plus atomic commits on any new project, without being asked. Never an unrequested push
4. **Real justifications**: every non-trivial technical choice states "X rather than Y, for this concrete reason". Empty justifications such as "robust" or "scalable" are banned

The installer copies it into `~/.vibe/prompts/` and switches `system_prompt_id` to `"cli-caveman"` in `config.toml`, with an automatic backup.

**After a major Vibe update**: the built-in prompt evolves while this copy stays frozen. Copy the new `cli.md` from the installed package and paste the four sections back at the end.

## What to know about Vibe

Vibe may not trigger skills automatically on keywords. They load through `/name`, or because the routing table in `AGENTS.md` and the system prompt tell the model to read the right `SKILL.md` before acting. Tested on an open-ended infrastructure prompt: the three relevant skills were read before anything was written.

## Updating

Re-run `bash install.sh` after a `git pull`. The previous `AGENTS.md` is backed up every time.

## License

Apache-2.0, see `LICENSE`. The file `vibe/prompts/cli-caveman.md` contains the built-in prompt of Mistral Vibe (Apache-2.0, Copyright Mistral AI), see `NOTICE`.
