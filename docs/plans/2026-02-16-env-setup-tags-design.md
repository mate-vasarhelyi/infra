# Design: env/setup tag split

## Problem

The `common` tag bundles user creation (`user-setup`) with all environment configuration. This means:
- Can't configure an existing user on an existing system without also running user-setup
- Can't target the currently logged-in user — always targets hardcoded `mate`

## Solution

Split `common` into two tags and introduce a `target_user` variable.

### Variables

```yaml
# group_vars/all/vars.yml
target_user: "{{ ansible_user_id }}"   # auto-detect logged-in user
username: mate                          # stays for desktop/thinkpad/media roles
```

### Tags

| Tag | Purpose | Roles |
|-----|---------|-------|
| `env` | Configure existing user's environment | base-packages, zsh, git, starship, ssh, fonts, tailscale, claude-code, jira-cli, docker, custom-scripts |
| `setup` | Create user + configure environment | user-setup + all `env` roles |
| `desktop` | Desktop environment (unchanged) | i3, rofi, dunst, kitty, touchpad |
| `media` | Docker stacks (unchanged) | docker-stacks |
| `thinkpad-x1` | Device-specific (unchanged) | fingerprint, tlp, accelerometer, wwan |

### site.yml structure

```yaml
roles:
  - { role: user-setup,      tags: [setup] }
  - { role: base-packages,   tags: [env, setup] }
  - { role: zsh,             tags: [env, setup] }
  - { role: git,             tags: [env, setup] }
  - { role: starship,        tags: [env, setup] }
  - { role: ssh,             tags: [env, setup] }
  - { role: fonts,           tags: [env, setup] }
  - { role: tailscale,       tags: [env, setup] }
  - { role: claude-code,     tags: [env, setup] }
  - { role: jira-cli,        tags: [env, setup] }
  - { role: docker,          tags: [env, setup] }
  - { role: custom-scripts,  tags: [env, setup] }
  # desktop, media, thinkpad-x1 unchanged
```

### Role changes

Roles with user paths migrate `{{ username }}` to `{{ target_user }}`:
- `user-setup` — creates `target_user`
- `zsh` — shell + `.zshrc`
- `git` — `.gitconfig` + gh config
- `ssh` — `.ssh/` dir + keys
- `claude-code` — install + configs
- `jira-cli` — config
- `custom-scripts` — scripts in `~/.local/bin/`
- `docker` — adds `target_user` to docker group

Roles with no user paths (tag update only):
- `base-packages`, `starship`, `fonts`, `tailscale`

Roles unchanged (stay on `{{ username }}`):
- `i3`, `rofi`, `dunst`, `kitty`, `touchpad`
- `fingerprint`, `tlp`, `accelerometer`, `wwan`
- `docker-stacks`

### Usage

```bash
# Existing system — configures current user
ansible-playbook site.yml --tags env --ask-vault-pass

# New system — creates user 'mate' then configures
ansible-playbook site.yml --tags setup -e target_user=mate --ask-vault-pass

# New system — creates current user (default)
ansible-playbook site.yml --tags setup --ask-vault-pass
```
