# Ansible Config Empire — Design Document

## Goal

A single Git repository that configures any machine — laptops, LXC containers, and eventually macOS — from a fresh install to a fully working environment with one command. Public repo, secrets encrypted with Ansible Vault.

## Current State

Dotfiles managed via bare git repo at `~/.dotfiles` tracking 4 files (.bashrc, .zshrc, i3/config, kitty.conf). Significant configs untracked: 24 i3 scripts, rofi, dunst, custom scripts, Claude Code setup, system-level configs (TLP, touchpad, fingerprint, WWAN). 218 packages installed. No existing Ansible work.

## Architecture: Fine-Grained Roles with Runtime Tags

### Repo Structure

```
~/.infra/
├── bootstrap.sh                # installs git+ansible, clones repo
├── site.yml                    # single entry-point playbook
├── ansible.cfg                 # roles_path, vault settings
├── requirements.yml            # ansible-galaxy dependencies
├── .gitignore                  # .vault-pass, *.retry
│
├── group_vars/
│   └── all/
│       ├── vars.yml            # shared variables (references vault_ vars)
│       └── vault.yml           # ansible-vault encrypted secrets
│
├── host_vars/
│   └── thinkpad-x1.yml        # device-specific vars
│
├── roles/
│   ├── base-packages/          # core CLI tools
│   ├── zsh/                    # zsh + config
│   ├── git/                    # git + gitconfig
│   ├── starship/               # starship prompt
│   ├── ssh/                    # ssh keys + config
│   ├── fonts/                  # FiraCode Nerd Font, Noto Sans, FontAwesome
│   ├── i3/                     # i3 + i3blocks + scripts
│   ├── rofi/                   # rofi + themes
│   ├── dunst/                  # notification daemon
│   ├── kitty/                  # terminal config
│   ├── touchpad/               # libinput xorg config
│   ├── claude-code/            # install script + configs + plugins
│   ├── custom-scripts/         # auto-rotate, sudo-askpass, run-claude
│   ├── docker/                 # docker engine + compose plugin
│   ├── docker-stacks/          # deploys compose files + .env from vault
│   ├── tailscale/              # tailscale install + auth
│   ├── fingerprint/            # fprintd + PAM config
│   ├── tlp/                    # battery/power management
│   ├── accelerometer/          # iio-sensor-proxy + auto-rotate
│   └── wwan/                   # ModemManager + FCC unlock + NM connection
│
└── stacks/                     # docker compose definitions
    ├── media/
    │   ├── docker-compose.yml
    │   └── .env.j2
    └── .../
```

Each role follows standard Ansible structure: `tasks/`, `files/`, `templates/`, `handlers/`, `defaults/`.

### Tag System

Tags select what to install at runtime. They layer:

```
Layer 1 - Base:        common
Layer 2 - Environment: desktop | server
Layer 3 - Purpose:     media | dev | monitoring | ...
Layer 4 - Device:      thinkpad-x1 | macbook | ...
```

Tag-to-role mapping in `site.yml`:

| Tag | Roles |
|-----|-------|
| `common` | base-packages, zsh, git, starship, ssh, fonts |
| `desktop` | i3, rofi, dunst, kitty, touchpad |
| `server` | docker, tailscale |
| `media` | docker, docker-stacks (stack=media) |
| `dev` | claude-code, custom-scripts |
| `thinkpad-x1` | fingerprint, tlp, accelerometer, wwan |

A role can have multiple tags (e.g. `docker` is tagged both `server` and `media`).

Example commands:

```bash
# This ThinkPad
ansible-playbook site.yml --tags common,desktop,dev,thinkpad-x1 --ask-vault-pass

# Media LXC
ansible-playbook site.yml --tags common,server,media --ask-vault-pass

# Dev LXC
ansible-playbook site.yml --tags common,dev --ask-vault-pass

# Just update docker stacks
ansible-playbook site.yml --tags media
```

### site.yml

```yaml
- hosts: localhost
  connection: local
  become: true

  pre_tasks:
    - name: Gather facts
      setup:
      tags: always

  roles:
    # common
    - { role: base-packages,  tags: [common] }
    - { role: zsh,            tags: [common] }
    - { role: git,            tags: [common] }
    - { role: starship,       tags: [common] }
    - { role: ssh,            tags: [common] }
    - { role: fonts,          tags: [common] }

    # desktop
    - { role: i3,             tags: [desktop] }
    - { role: rofi,           tags: [desktop] }
    - { role: dunst,          tags: [desktop] }
    - { role: kitty,          tags: [desktop] }
    - { role: touchpad,       tags: [desktop] }

    # server / services
    - { role: docker,         tags: [server, media] }
    - { role: tailscale,      tags: [server] }

    # purpose
    - { role: docker-stacks,  tags: [media], vars: { stack: media } }

    # dev tools
    - { role: claude-code,    tags: [dev] }
    - { role: custom-scripts, tags: [dev] }

    # device-specific
    - { role: fingerprint,    tags: [thinkpad-x1] }
    - { role: tlp,            tags: [thinkpad-x1] }
    - { role: accelerometer,  tags: [thinkpad-x1] }
    - { role: wwan,           tags: [thinkpad-x1] }
```

## Multi-Distro Strategy

Each role dispatches to distro-specific task files when needed:

```yaml
# roles/zsh/tasks/main.yml
- name: Install zsh
  package:
    name: zsh
    state: present

- name: Include distro-specific tasks
  include_tasks: "{{ ansible_os_family | lower }}.yml"
  when: ansible_os_family in ['Archlinux', 'Debian', 'Darwin']
```

The `package` module handles cases where package names match across distros. Distro-specific task files (e.g. `archlinux.yml`, `debian.yml`) handle differences in package names, AUR packages, or platform-specific paths.

Package name mapping via role defaults:

```yaml
# roles/base-packages/defaults/main.yml
base_packages_common: [curl, wget, htop, jq, tree, unzip]
base_packages_archlinux: [ripgrep, fd, bat, yay]
base_packages_debian: [ripgrep, fd-find, bat]
```

Desktop-only roles skip on incompatible systems:

```yaml
- name: Skip on non-Linux
  meta: end_play
  when: ansible_system != 'Linux'
```

macOS: Add `darwin.yml` task files to relevant roles and a `brew` role when needed. No structural changes required.

## Secrets Management — Ansible Vault

### Structure

```yaml
# group_vars/all/vault.yml (encrypted)
vault_sonarr_api_key: "abc123..."
vault_radarr_api_key: "def456..."
vault_tailscale_auth_key: "..."
vault_ssh_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
```

```yaml
# group_vars/all/vars.yml (plaintext, references vault)
sonarr_api_key: "{{ vault_sonarr_api_key }}"
radarr_api_key: "{{ vault_radarr_api_key }}"
```

Convention: All secrets prefixed with `vault_`. Plaintext `vars.yml` re-maps them so the full variable list is visible without decrypting.

### Workflow

```bash
ansible-vault create group_vars/all/vault.yml    # first time
ansible-vault edit group_vars/all/vault.yml      # edit later
ansible-playbook site.yml --ask-vault-pass        # prompt for passphrase
```

Optional: store passphrase in `.vault-pass` (gitignored) and set `vault_password_file = .vault-pass` in `ansible.cfg` to skip the prompt.

### Docker .env Templates

```jinja2
# stacks/media/.env.j2
SONARR_API_KEY={{ sonarr_api_key }}
TZ=Europe/Budapest
PUID=1000
PGID=1000
```

Templated to `/opt/docker/media/.env` at deploy time.

## Docker Stacks — Full Lifecycle

The `docker-stacks` role creates directories, deploys compose files, templates `.env` from vault, and manages container lifecycle:

```yaml
# roles/docker-stacks/tasks/main.yml
- name: Create stack directory
  file:
    path: "/opt/docker/{{ stack }}"
    state: directory

- name: Deploy docker-compose.yml
  copy:
    src: "{{ playbook_dir }}/stacks/{{ stack }}/docker-compose.yml"
    dest: "/opt/docker/{{ stack }}/docker-compose.yml"
  notify: restart stack

- name: Template .env file
  template:
    src: "{{ playbook_dir }}/stacks/{{ stack }}/.env.j2"
    dest: "/opt/docker/{{ stack }}/.env"
    mode: "0600"
  notify: restart stack

- name: Start stack
  community.docker.docker_compose_v2:
    project_src: "/opt/docker/{{ stack }}"
    state: present
```

Handler restarts the stack when compose or .env files change.

Adding a new stack: create `stacks/<name>/docker-compose.yml` + `.env.j2`, add vault vars, add role entry in `site.yml` with a new tag.

## Bootstrap Script

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/mate-vasarhelyi/infra.git"
CLONE_DIR="$HOME/.infra"

echo "=== Config Empire Bootstrap ==="

if command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm git ansible
elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y git ansible
elif command -v brew &>/dev/null; then
    brew install git ansible
else
    echo "Unsupported package manager."
    exit 1
fi

if [ -d "$CLONE_DIR" ]; then
    git -C "$CLONE_DIR" pull
else
    git clone "$REPO" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

if [ -f requirements.yml ]; then
    ansible-galaxy install -r requirements.yml
fi

echo ""
echo "Ready! Run:"
echo "  cd $CLONE_DIR"
echo "  ansible-playbook site.yml --tags common,desktop --ask-vault-pass"
```

Public repo, HTTPS clone. SSH remote added after the `ssh` role deploys keys.

## Claude Code Role

- Installs via official `curl -fsSL https://console.anthropic.com/install.sh | sh`
- Templates `CLAUDE.md.j2` (device-specific system info varies per host)
- Templates `settings.local.json.j2` (permissions may vary)
- Copies `settings.json` (static, same everywhere)
- Installs plugins via `claude plugins install` loop
- All tasks run as user (`become: false`)
