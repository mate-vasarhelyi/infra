# Jira CLI Role Design

**Date:** 2026-02-14
**Status:** Approved

## Problem

Need jira-cli ([ankitpokhrel/jira-cli](https://github.com/ankitpokhrel/jira-cli)) installed and configured with Atlassian Cloud authentication managed through Ansible vault, so credentials are reproducible and not manually configured.

## Decision

New `jira-cli` role under the `common` tag. Installs the binary, templates the config file, and exports the API token via zshrc.

## Design

### Installation

- **Arch**: `jira-cli` package from AUR via yay
- **Debian**: Binary download from GitHub releases to `/usr/local/bin/jira`

### Configuration

Config file: `~/.config/.jira/.config.yml` (jira-cli's default XDG location)

Templated from Ansible vars with:
- `jira_server` — Atlassian Cloud URL (e.g. `https://org.atlassian.net`)
- `jira_login` — Atlassian account email
- `jira_project_key` — default project key
- `jira_installation_type` — `Cloud` (hardcoded default)

Board and issue type fields left for manual population via `jira init` after first run — these require API calls to discover IDs.

### Authentication

Cloud Jira uses API tokens from `id.atlassian.com/manage-profile/security/api-tokens`.

- Token stored in vault as `vault_jira_api_token`
- Exported as `JIRA_API_TOKEN` env var in `zshrc.j2`, gated on `jira_api_token is defined`
- Same conditional pattern as existing `SUDO_ASKPASS` export

### Vault additions

```yaml
# vault.yml (encrypted)
vault_jira_api_token: <token>
vault_jira_server: https://org.atlassian.net
vault_jira_login: user@example.com
```

```yaml
# vars.yml
jira_api_token: "{{ vault_jira_api_token }}"
jira_server: "{{ vault_jira_server }}"
jira_login: "{{ vault_jira_login }}"
```

### Files

| Action | Path |
|--------|------|
| Create | `roles/jira-cli/tasks/main.yml` |
| Create | `roles/jira-cli/tasks/archlinux.yml` |
| Create | `roles/jira-cli/tasks/debian.yml` |
| Create | `roles/jira-cli/templates/config.yml.j2` |
| Create | `roles/jira-cli/defaults/main.yml` |
| Modify | `roles/zsh/templates/zshrc.j2` |
| Modify | `group_vars/all/vars.yml` |
| Modify | `group_vars/all/vault.yml` |
| Modify | `site.yml` |

### Security

- API token in vault (encrypted at rest), deployed to zshrc with `mode: "0644"` (standard for .zshrc, token only visible to user's shell)
- Config file deployed with `mode: "0600"` (contains login email)
- `no_log: true` on tasks that handle the token

### Trade-offs

**What it does:** Installs jira-cli, configures server/project/auth so `jira issue list` works immediately after Ansible run.

**What it doesn't do:** Populate board IDs and issue types — these require live API calls. User runs `jira init` once to fill these in, or adds them to the template manually.
