---
name: init
description: Analyses a project once and generates an AGENTS.md at its root (stack, key commands, conventions, relevant skills). Run it when starting work on a new repository. Triggers on "init", "initialise the project", "onboard", "generate AGENTS.md", "discover the project".
user-invocable: true
---

# /init: project discovery, once

Goal: produce an `AGENTS.md` at the repository root summarising the project, so that later sessions start already informed. Do it once per project, or after a major change of stack.

Do NOT reload everything at every session: this file exists precisely to avoid that.

## Step 1, scan the structure

- List the project tree (main directories, reasonable depth, ignoring `node_modules`, `.git`, `dist`, `vendor`, `.terraform`).
- Spot the entry points and the general layout.

## Step 2, detect the stack

Look for the markers and infer the technologies:

- Language and packages: `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `Gemfile`.
- Containers: `Dockerfile`, `docker-compose.yml`, `docker-stack.yml`.
- IaC: `*.tf`, `main.tf` (Terraform), `Chart.yaml` (Helm), `playbook.yml` or `roles/` (Ansible).
- Kubernetes and GitOps: `k8s/`, `manifests/`, an ArgoCD `Application`.
- CI/CD: `.github/workflows/`, `.gitlab-ci.yml`.
- Monitoring: `prometheus.yml`, Grafana dashboards.

## Step 3, read the docs and conventions

- `README.md`: purpose of the project, install, usage.
- `CONTRIBUTING.md`: contribution rules, commit format, branches.
- `.editorconfig`, linter and formatter configuration.
- `git log --oneline -15` and `git branch -a`: the real commit style and branch naming.

## Step 4, load the relevant skills

Vibe does NOT trigger skills on its own. So, depending on the detected stack, directly read the file of the relevant skill with read_file to load its method into context:

`~/.vibe/skills/<name>/SKILL.md`

Stack to skill mapping:

- Terraform: `terraform-guide`
- Helm and Kubernetes: `helm-chart-builder`
- Ansible: `ansible-playbook-builder`
- Docker Swarm: `docker-swarm-guide`
- ArgoCD and GitOps: `argocd-guide`
- Prometheus and Grafana: `prometheus-grafana-setup`
- Azure: `azure-cloud-advisor`
- GitHub Actions: `github-actions-expert`
- GitLab CI: `gitlab-ci-guide`
- Always (code, commit, branch): `dev-conventions`

Read ONLY the skills matching the real stack of the project, not all eleven. `dev-conventions`: always read it.

## Step 5, write ./AGENTS.md at the root

Generate a SHORT file, not an essay. Template:

```markdown
# AGENTS.md, <project name>

## Stack
<languages, frameworks, infrastructure tools detected>

## Key commands
- Build: <cmd>
- Test: <cmd>
- Lint and format: <cmd>
- Run locally: <cmd>

## Conventions
- Commits: <format observed in git log>
- Branches: <pattern observed in git branch>
- Code style: <from .editorconfig or the linter>

## Relevant skills
<list of the skills from step 4>

## Known pitfalls
<gotchas spotted: non-obvious setup, a service to start first, and so on>
```

Writing rules:

- One piece of information per line, airy, bold on the anchors.
- Record only what is NOT obvious, what the code does not say by itself.
- Do not copy the README wholesale, point at it.
- Never the em dash.

## After generating

Show a brief summary to the user: detected stack, selected skills, path of the written file. Do not commit unless asked.
