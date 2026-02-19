# Docker Dev Environment Design

## Goal

Provide a Dockerfile and supporting files so others can spin up the same dev environment that currently runs on Proxmox LXC containers, using Docker instead.

## Scope

- Tags: `setup,remote-dev` (user-setup + all env roles + code-server/ttyd)
- Base image: Debian bookworm
- CLI/dev tools only, no desktop/GUI
- Secrets skipped entirely -- users authenticate manually on first use

## Approach: Bake at Build Time

The Dockerfile installs Ansible, copies the repo, runs the playbook at build time, then cleans up. The resulting image is a ready-to-use dev environment.

**Why not run-at-start:** Slow startup (reinstalls packages every boot), fragile (network failures break the container), larger image (Ansible stays).

**Why not multi-stage:** Over-engineered -- systemd services and scattered install paths don't transfer cleanly between stages.

## Vault-Free Execution

A `docker-defaults.yml` file provides safe placeholder values for vault-referenced variables:

```yaml
user_password: "changeme"
git_email: "dev@localhost"
github_token: "replace_me"
```

All other vault vars (SSH keys, claude token, jira config) are left undefined. Tasks skip via existing or newly-added `when:` guards.

### What users get without secrets

| Tool | Installed? | Pre-authenticated? | Manual step |
|------|-----------|-------------------|-------------|
| Claude Code | Yes | No | Run `claude`, OAuth login in browser |
| Jira CLI | Yes | No | Run `jira init` |
| Git/GitHub CLI | Yes | No | `git config --global user.email`, `gh auth login` |
| SSH | Yes (no keys) | No | `ssh-keygen` or mount keys |

## Role Changes Required

Two small guard additions:

1. **claude-code** (`roles/claude-code/tasks/main.yml`): Add `when: claude_oauth_refresh_token is defined` to credentials.json deploy task
2. **jira-cli** (`roles/jira-cli/tasks/main.yml`): Change guard from `when: jira_server is defined` to `when: jira_server is defined and jira_login is defined`

## New Files

### `Dockerfile` (repo root)

- `FROM debian:bookworm`
- Install Ansible + python3-passlib + sudo + git
- Copy repo, install Galaxy deps
- Run playbook with `--tags setup,remote-dev --extra-vars "@docker-defaults.yml" --extra-vars "target_user=dev"`
- Clean up Ansible and build artifacts
- Switch to `dev` user, expose ports 8080 (code-server) and 7681 (ttyd)
- Entrypoint starts both services

### `docker-entrypoint.sh` (repo root)

Starts code-server (backgrounded) and ttyd+zellij (foreground, keeps container alive). No systemd -- processes run directly.

```bash
#!/bin/bash
code-server --bind-addr 0.0.0.0:8080 --auth none &
ttyd -p 7681 -W zellij
```

### `docker-defaults.yml` (repo root)

Placeholder values for vault-referenced vars used by setup/remote-dev tags.

### `.dockerignore` (repo root)

Excludes `.git`, `.vault-pass`, `*.retry`, `docs/`.

## Usage

```bash
docker build -t infra-dev .
docker run -d -p 8080:8080 -p 7681:7681 infra-dev

# code-server: http://localhost:8080
# ttyd+zellij: http://localhost:7681
```
