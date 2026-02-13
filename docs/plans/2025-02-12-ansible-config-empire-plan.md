# Ansible Config Empire — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a public Ansible repo at `~/.infra` that configures any machine (Arch laptop, Debian LXC, eventually macOS) from a fresh install via tagged roles with Ansible Vault secrets.

**Architecture:** Fine-grained roles (one per tool/concern), single `site.yml` entry point, runtime `--tags` for selecting what to apply. Multi-distro via `ansible_os_family` dispatch per role. Docker stacks managed full-lifecycle with templated `.env` files from vault.

**Tech Stack:** Ansible, Jinja2 templates, Ansible Vault, Docker Compose, bash (bootstrap)

**Design doc:** `docs/plans/2025-02-12-ansible-config-empire-design.md`

---

### Task 1: Create repo scaffold at ~/.infra

**Files:**
- Create: `~/.infra/ansible.cfg`
- Create: `~/.infra/site.yml`
- Create: `~/.infra/.gitignore`
- Create: `~/.infra/requirements.yml`
- Create: `~/.infra/group_vars/all/vars.yml`
- Create: `~/.infra/host_vars/thinkpad-x1.yml`

**Step 1: Initialize the repo**

```bash
mkdir -p ~/.infra
cd ~/.infra
git init
git branch -m main
```

**Step 2: Create `ansible.cfg`**

```ini
[defaults]
roles_path = roles
vault_password_file = .vault-pass
host_key_checking = False
```

**Step 3: Create `.gitignore`**

```
.vault-pass
*.retry
```

**Step 4: Create `requirements.yml`**

```yaml
collections:
  - name: community.docker
```

**Step 5: Create `site.yml` skeleton with all role entries**

```yaml
- hosts: localhost
  connection: local
  become: true

  vars:
    username: "{{ lookup('env', 'USER') }}"

  pre_tasks:
    - name: Gather facts
      ansible.builtin.setup:
      tags: always

  roles:
    # common
    - { role: base-packages,   tags: [common] }
    - { role: zsh,             tags: [common] }
    - { role: git,             tags: [common] }
    - { role: starship,        tags: [common] }
    - { role: ssh,             tags: [common] }
    - { role: fonts,           tags: [common] }

    # desktop
    - { role: i3,              tags: [desktop] }
    - { role: rofi,            tags: [desktop] }
    - { role: dunst,           tags: [desktop] }
    - { role: kitty,           tags: [desktop] }
    - { role: touchpad,        tags: [desktop] }

    # server / services
    - { role: docker,          tags: [server, media] }
    - { role: tailscale,       tags: [server] }

    # purpose
    - { role: docker-stacks,   tags: [media], vars: { stack: media } }

    # dev tools
    - { role: claude-code,     tags: [dev] }
    - { role: custom-scripts,  tags: [dev] }

    # device-specific
    - { role: fingerprint,     tags: [thinkpad-x1] }
    - { role: tlp,             tags: [thinkpad-x1] }
    - { role: accelerometer,   tags: [thinkpad-x1] }
    - { role: wwan,            tags: [thinkpad-x1] }
```

**Step 6: Create `group_vars/all/vars.yml`**

```yaml
username: mate
dotfiles_repo: "https://github.com/mate-vasarhelyi/infra.git"
timezone: Europe/Budapest
```

**Step 7: Create `host_vars/thinkpad-x1.yml`**

```yaml
# ThinkPad X1 Yoga Gen 6 specific
accelerometer_screen: "eDP-1"
accelerometer_touch_devices:
  - "SYNA8009:00 06CB:CE57 Touchpad"
  - "Wacom HID 5277 Finger"
  - "Wacom HID 5277 Pen"

tlp_start_charge: 75
tlp_stop_charge: 80

wwan_fcc_unlock_vid: "1eac"
wwan_fcc_unlock_pid: "1001"
```

**Step 8: Commit**

```bash
cd ~/.infra
git add -A
git commit -m "scaffold: init repo with ansible.cfg, site.yml, vars"
```

---

### Task 2: Create bootstrap.sh

**Files:**
- Create: `~/.infra/bootstrap.sh`

**Step 1: Write the bootstrap script**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/mate-vasarhelyi/infra.git"
CLONE_DIR="$HOME/.infra"

echo "=== Config Empire Bootstrap ==="

# Detect distro and install prerequisites
if command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm git ansible
elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y git ansible
elif command -v brew &>/dev/null; then
    brew install git ansible
else
    echo "Unsupported package manager. Install git and ansible manually."
    exit 1
fi

# Clone the repo
if [ -d "$CLONE_DIR" ]; then
    echo "Repo already exists at $CLONE_DIR, pulling latest..."
    git -C "$CLONE_DIR" pull
else
    git clone "$REPO" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

# Install ansible galaxy dependencies
if [ -f requirements.yml ]; then
    ansible-galaxy collection install -r requirements.yml
fi

echo ""
echo "Ready! Run your playbook:"
echo "  cd $CLONE_DIR"
echo "  ansible-playbook site.yml --tags common,desktop --ask-vault-pass"
```

**Step 2: Make it executable and commit**

```bash
cd ~/.infra
chmod +x bootstrap.sh
git add bootstrap.sh
git commit -m "add bootstrap.sh for fresh machine setup"
```

---

### Task 3: Set up Ansible Vault and secrets structure

**Files:**
- Create: `~/.infra/group_vars/all/vault.yml` (encrypted)

**Step 1: Create the vault file**

Run interactively — you'll be prompted for a passphrase:

```bash
cd ~/.infra
ansible-vault create group_vars/all/vault.yml
```

Put placeholder content (edit later with real secrets):

```yaml
# Secrets — all prefixed with vault_
vault_git_email: "your-email@example.com"
vault_placeholder: "replace_me"
```

**Step 2: Optionally create `.vault-pass` for convenience**

```bash
echo "your-passphrase-here" > ~/.infra/.vault-pass
chmod 600 ~/.infra/.vault-pass
```

This file is in `.gitignore` — never committed.

**Step 3: Update `group_vars/all/vars.yml` to reference vault vars**

Add to existing file:

```yaml
git_email: "{{ vault_git_email }}"
```

**Step 4: Commit**

```bash
cd ~/.infra
git add group_vars/all/vault.yml group_vars/all/vars.yml
git commit -m "add ansible vault with placeholder secrets"
```

---

### Task 4: Create the base-packages role (establishes multi-distro pattern)

**Files:**
- Create: `~/.infra/roles/base-packages/tasks/main.yml`
- Create: `~/.infra/roles/base-packages/tasks/archlinux.yml`
- Create: `~/.infra/roles/base-packages/tasks/debian.yml`
- Create: `~/.infra/roles/base-packages/defaults/main.yml`

**Step 1: Create role directory structure**

```bash
mkdir -p ~/.infra/roles/base-packages/{tasks,defaults}
```

**Step 2: Write `defaults/main.yml`**

```yaml
base_packages:
  - curl
  - wget
  - htop
  - jq
  - tree
  - unzip
  - man-db
  - openssh

base_packages_archlinux:
  - ripgrep
  - fd
  - bat
  - base-devel

base_packages_debian:
  - ripgrep
  - fd-find
  - bat
  - build-essential
```

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Install common packages
  ansible.builtin.package:
    name: "{{ base_packages }}"
    state: present

- name: Include distro-specific packages
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

**Step 4: Write `tasks/archlinux.yml`**

```yaml
- name: Install Arch-specific packages
  community.general.pacman:
    name: "{{ base_packages_archlinux }}"
    state: present

- name: Check if yay is installed
  ansible.builtin.command: which yay
  register: yay_check
  changed_when: false
  failed_when: false

- name: Install yay (AUR helper)
  when: yay_check.rc != 0
  become: true
  become_user: "{{ username }}"
  block:
    - name: Clone yay
      ansible.builtin.git:
        repo: https://aur.archlinux.org/yay.git
        dest: /tmp/yay-build
    - name: Build and install yay
      ansible.builtin.command: makepkg -si --noconfirm
      args:
        chdir: /tmp/yay-build
    - name: Clean up yay build
      ansible.builtin.file:
        path: /tmp/yay-build
        state: absent
```

**Step 5: Write `tasks/debian.yml`**

```yaml
- name: Install Debian-specific packages
  ansible.builtin.apt:
    name: "{{ base_packages_debian }}"
    state: present
    update_cache: true
```

**Step 6: Test the role**

```bash
cd ~/.infra
ansible-playbook site.yml --tags common --check --diff
```

Expected: Dry run shows package install tasks, no errors.

**Step 7: Run for real**

```bash
cd ~/.infra
ansible-playbook site.yml --tags common
```

Expected: Packages already installed (since this is your current machine), so most tasks show "ok".

**Step 8: Commit**

```bash
cd ~/.infra
git add roles/base-packages/
git commit -m "role: base-packages with multi-distro support"
```

---

### Task 5: Create the zsh role

**Files:**
- Create: `~/.infra/roles/zsh/tasks/main.yml`
- Create: `~/.infra/roles/zsh/templates/zshrc.j2`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/zsh/{tasks,templates}
```

**Step 2: Write `templates/zshrc.j2`**

Migrated from current `~/.zshrc`:

```
# History
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000
bindkey -e

# Completion
zstyle :compinstall filename '{{ ansible_env.HOME }}/.zshrc'
autoload -Uz compinit
compinit

# SUDO_ASKPASS
{% if ansible_os_family != 'Darwin' %}
export SUDO_ASKPASS="$HOME/.local/bin/sudo-askpass"
{% endif %}

# PATH
export PATH="$HOME/.local/bin:$PATH"

# Aliases
alias ll='ls -la'
alias la='ls -a'

# Infra repo management
alias infra='cd ~/.infra'

# Starship prompt
eval "$(starship init zsh)"
```

Note: The old `dotfiles` alias is replaced with `infra` alias. The SUDO_ASKPASS is conditional (not needed on macOS/servers without rofi).

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Install zsh
  ansible.builtin.package:
    name: zsh
    state: present

- name: Set zsh as default shell
  ansible.builtin.user:
    name: "{{ username }}"
    shell: /usr/bin/zsh

- name: Deploy .zshrc
  ansible.builtin.template:
    src: zshrc.j2
    dest: "/home/{{ username }}/.zshrc"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"
```

**Step 4: Test and run**

```bash
cd ~/.infra
ansible-playbook site.yml --tags common --check --diff
ansible-playbook site.yml --tags common
```

**Step 5: Commit**

```bash
cd ~/.infra
git add roles/zsh/
git commit -m "role: zsh with templated zshrc"
```

---

### Task 6: Create the git role

**Files:**
- Create: `~/.infra/roles/git/tasks/main.yml`
- Create: `~/.infra/roles/git/templates/gitconfig.j2`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/git/{tasks,templates}
```

**Step 2: Write `templates/gitconfig.j2`**

```
[user]
	name = {{ git_user_name }}
	email = {{ git_email }}
[init]
	defaultBranch = main
```

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Install git
  ansible.builtin.package:
    name: git
    state: present

- name: Deploy .gitconfig
  ansible.builtin.template:
    src: gitconfig.j2
    dest: "/home/{{ username }}/.gitconfig"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"
```

**Step 4: Add vars**

Add to `group_vars/all/vars.yml`:

```yaml
git_user_name: "Mate Vasarhelyi"
```

`git_email` already references vault.

**Step 5: Commit**

```bash
cd ~/.infra
git add roles/git/ group_vars/all/vars.yml
git commit -m "role: git with templated gitconfig"
```

---

### Task 7: Create the starship role

**Files:**
- Create: `~/.infra/roles/starship/tasks/main.yml`
- Create: `~/.infra/roles/starship/tasks/archlinux.yml`
- Create: `~/.infra/roles/starship/tasks/debian.yml`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/starship/tasks
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Include distro-specific install
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

**Step 3: Write `tasks/archlinux.yml`**

```yaml
- name: Install starship
  community.general.pacman:
    name: starship
    state: present
```

**Step 4: Write `tasks/debian.yml`**

```yaml
- name: Install starship via install script
  ansible.builtin.shell: |
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
  args:
    creates: /usr/local/bin/starship
  become: true
```

**Step 5: Commit**

```bash
cd ~/.infra
git add roles/starship/
git commit -m "role: starship prompt with multi-distro install"
```

---

### Task 8: Create the ssh role

**Files:**
- Create: `~/.infra/roles/ssh/tasks/main.yml`

This role ensures `~/.ssh` exists with correct permissions. SSH key deployment from vault is optional — add to vault when ready.

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/ssh/tasks
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Ensure .ssh directory exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.ssh"
    state: directory
    owner: "{{ username }}"
    mode: "0700"

- name: Deploy SSH private key from vault
  ansible.builtin.copy:
    content: "{{ vault_ssh_private_key }}"
    dest: "/home/{{ username }}/.ssh/id_ed25519"
    owner: "{{ username }}"
    mode: "0600"
  when: vault_ssh_private_key is defined
  no_log: true

- name: Deploy SSH public key from vault
  ansible.builtin.copy:
    content: "{{ vault_ssh_public_key }}"
    dest: "/home/{{ username }}/.ssh/id_ed25519.pub"
    owner: "{{ username }}"
    mode: "0644"
  when: vault_ssh_public_key is defined
```

**Step 3: Commit**

```bash
cd ~/.infra
git add roles/ssh/
git commit -m "role: ssh directory and optional key deployment from vault"
```

---

### Task 9: Create the fonts role

**Files:**
- Create: `~/.infra/roles/fonts/tasks/main.yml`
- Create: `~/.infra/roles/fonts/tasks/archlinux.yml`
- Create: `~/.infra/roles/fonts/tasks/debian.yml`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/fonts/tasks
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Include distro-specific font install
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

**Step 3: Write `tasks/archlinux.yml`**

```yaml
- name: Install fonts (Arch)
  community.general.pacman:
    name:
      - noto-fonts
      - ttf-firacode-nerd
      - ttf-font-awesome
    state: present
```

**Step 4: Write `tasks/debian.yml`**

```yaml
- name: Install fonts (Debian)
  ansible.builtin.apt:
    name:
      - fonts-noto
      - fonts-font-awesome
    state: present

- name: Install FiraCode Nerd Font (Debian)
  ansible.builtin.shell: |
    mkdir -p /usr/local/share/fonts/FiraCodeNerd
    cd /tmp
    curl -fLo FiraCode.tar.xz https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz
    tar -xf FiraCode.tar.xz -C /usr/local/share/fonts/FiraCodeNerd
    fc-cache -fv
    rm -f FiraCode.tar.xz
  args:
    creates: /usr/local/share/fonts/FiraCodeNerd
```

**Step 5: Commit**

```bash
cd ~/.infra
git add roles/fonts/
git commit -m "role: fonts with FiraCode Nerd Font, Noto, FontAwesome"
```

---

### Task 10: Create the kitty role

**Files:**
- Create: `~/.infra/roles/kitty/tasks/main.yml`
- Create: `~/.infra/roles/kitty/files/kitty.conf`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/kitty/{tasks,files}
```

**Step 2: Copy current kitty config as `files/kitty.conf`**

```
font_family FiraCode Nerd Font
font_size 11
```

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Install kitty
  ansible.builtin.package:
    name: kitty
    state: present

- name: Ensure kitty config directory exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.config/kitty"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"

- name: Deploy kitty.conf
  ansible.builtin.copy:
    src: kitty.conf
    dest: "/home/{{ username }}/.config/kitty/kitty.conf"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"
```

**Step 4: Commit**

```bash
cd ~/.infra
git add roles/kitty/
git commit -m "role: kitty terminal with FiraCode config"
```

---

### Task 11: Create the i3 role

This is the biggest role — i3 config, i3blocks config, and all 24 scripts.

**Files:**
- Create: `~/.infra/roles/i3/tasks/main.yml`
- Create: `~/.infra/roles/i3/tasks/archlinux.yml`
- Create: `~/.infra/roles/i3/tasks/debian.yml`
- Create: `~/.infra/roles/i3/files/config`
- Create: `~/.infra/roles/i3/files/i3blocks.conf`
- Create: `~/.infra/roles/i3/files/scripts/` (all 24 scripts)

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/i3/{tasks,files/scripts}
```

**Step 2: Copy all i3 files from current system**

```bash
cp ~/.config/i3/config ~/.infra/roles/i3/files/config
cp ~/.config/i3/i3blocks.conf ~/.infra/roles/i3/files/i3blocks.conf
cp ~/.config/i3/scripts/* ~/.infra/roles/i3/files/scripts/
```

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Skip on non-Linux
  ansible.builtin.meta: end_play
  when: ansible_system != 'Linux'

- name: Include distro-specific install
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"

- name: Ensure i3 config directories exist
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  loop:
    - "/home/{{ username }}/.config/i3"
    - "/home/{{ username }}/.config/i3/scripts"
  become: true
  become_user: "{{ username }}"

- name: Deploy i3 config
  ansible.builtin.copy:
    src: config
    dest: "/home/{{ username }}/.config/i3/config"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"

- name: Deploy i3blocks config
  ansible.builtin.copy:
    src: i3blocks.conf
    dest: "/home/{{ username }}/.config/i3/i3blocks.conf"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"

- name: Deploy i3 scripts
  ansible.builtin.copy:
    src: scripts/
    dest: "/home/{{ username }}/.config/i3/scripts/"
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"
```

**Step 4: Write `tasks/archlinux.yml`**

```yaml
- name: Install i3 and dependencies (Arch)
  community.general.pacman:
    name:
      - i3-wm
      - i3blocks
      - i3lock
      - i3status
      - feh
      - xss-lock
      - scrot
      - playerctl
      - polkit-gnome
      - dex
      - xdg-user-dirs
    state: present
```

**Step 5: Write `tasks/debian.yml`**

```yaml
- name: Install i3 and dependencies (Debian)
  ansible.builtin.apt:
    name:
      - i3
      - i3blocks
      - i3lock
      - feh
      - xss-lock
      - scrot
      - playerctl
      - policykit-1-gnome
      - dex
    state: present
```

**Step 6: Commit**

```bash
cd ~/.infra
git add roles/i3/
git commit -m "role: i3wm with config, i3blocks, and all scripts"
```

---

### Task 12: Create the rofi role

**Files:**
- Create: `~/.infra/roles/rofi/tasks/main.yml`
- Create: `~/.infra/roles/rofi/files/` (all rofi config files)

**Step 1: Create role structure and copy configs**

```bash
mkdir -p ~/.infra/roles/rofi/{tasks,files}
cp ~/.config/rofi/* ~/.infra/roles/rofi/files/
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Install rofi
  ansible.builtin.package:
    name: rofi
    state: present

- name: Ensure rofi config directory exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.config/rofi"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"

- name: Deploy rofi configs
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/home/{{ username }}/.config/rofi/"
    owner: "{{ username }}"
    mode: "0644"
  with_fileglob:
    - "files/*"
  become: true
  become_user: "{{ username }}"
```

**Step 3: Commit**

```bash
cd ~/.infra
git add roles/rofi/
git commit -m "role: rofi with all theme configs"
```

---

### Task 13: Create the dunst role

**Files:**
- Create: `~/.infra/roles/dunst/tasks/main.yml`
- Create: `~/.infra/roles/dunst/files/dunstrc`

**Step 1: Create role structure and copy config**

```bash
mkdir -p ~/.infra/roles/dunst/{tasks,files}
cp ~/.config/dunst/dunstrc ~/.infra/roles/dunst/files/dunstrc
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Install dunst
  ansible.builtin.package:
    name: dunst
    state: present

- name: Ensure dunst config directory exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.config/dunst"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"

- name: Deploy dunstrc
  ansible.builtin.copy:
    src: dunstrc
    dest: "/home/{{ username }}/.config/dunst/dunstrc"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"
```

**Step 3: Commit**

```bash
cd ~/.infra
git add roles/dunst/
git commit -m "role: dunst notification daemon"
```

---

### Task 14: Create the touchpad role

**Files:**
- Create: `~/.infra/roles/touchpad/tasks/main.yml`
- Create: `~/.infra/roles/touchpad/files/30-touchpad.conf`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/touchpad/{tasks,files}
```

**Step 2: Write `files/30-touchpad.conf`**

```
Section "InputClass"
    Identifier "touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "NaturalScrolling" "true"
EndSection
```

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Skip on non-Linux
  ansible.builtin.meta: end_play
  when: ansible_system != 'Linux'

- name: Deploy touchpad xorg config
  ansible.builtin.copy:
    src: 30-touchpad.conf
    dest: /etc/X11/xorg.conf.d/30-touchpad.conf
    mode: "0644"
```

**Step 4: Commit**

```bash
cd ~/.infra
git add roles/touchpad/
git commit -m "role: touchpad with natural scrolling"
```

---

### Task 15: Create the claude-code role

**Files:**
- Create: `~/.infra/roles/claude-code/tasks/main.yml`
- Create: `~/.infra/roles/claude-code/templates/CLAUDE.md.j2`
- Create: `~/.infra/roles/claude-code/templates/settings.local.json.j2`
- Create: `~/.infra/roles/claude-code/files/settings.json`
- Create: `~/.infra/roles/claude-code/defaults/main.yml`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/claude-code/{tasks,templates,files,defaults}
```

**Step 2: Write `defaults/main.yml`**

```yaml
claude_plugins:
  - superpowers@claude-plugins-official
```

**Step 3: Write `files/settings.json`**

```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  }
}
```

**Step 4: Write `templates/CLAUDE.md.j2`**

```
# System

- OS: {{ ansible_distribution }}{% if desktop_wm is defined %}, {{ desktop_wm }}{% endif %}

- Shell: zsh (minimal, no oh-my-zsh)
{% if 'desktop' in ansible_play_tags | default([]) %}
- Terminal: kitty (FiraCode Nerd Font)
- Browser: Zen
{% endif %}

# Infrastructure

Managed via Ansible repo at `~/.infra`.

```
cd ~/.infra
ansible-playbook site.yml --tags <tags> --ask-vault-pass
```

{% if ansible_os_family != 'Darwin' %}
# Sudo in Claude Code

Use `sudo -A` for privileged commands — rofi askpass popup at `~/.local/bin/sudo-askpass`.
Fallback: write commands to `/tmp/claude-pending.sh`, user runs `run-claude` in another terminal.
{% endif %}
```

**Step 5: Write `templates/settings.local.json.j2`**

This is a minimal starting point — permissions accumulate as you use Claude Code:

```json
{
  "permissions": {
    "allow": []
  }
}
```

**Step 6: Write `tasks/main.yml`**

```yaml
- name: Install Claude Code via official script
  ansible.builtin.shell: |
    curl -fsSL https://console.anthropic.com/install.sh | sh
  args:
    creates: "/home/{{ username }}/.local/bin/claude"
  become: true
  become_user: "{{ username }}"

- name: Ensure ~/.claude directory exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.claude"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"

- name: Deploy CLAUDE.md
  ansible.builtin.template:
    src: CLAUDE.md.j2
    dest: "/home/{{ username }}/.claude/CLAUDE.md"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"

- name: Deploy settings.json
  ansible.builtin.copy:
    src: settings.json
    dest: "/home/{{ username }}/.claude/settings.json"
    owner: "{{ username }}"
    mode: "0644"
  become: true
  become_user: "{{ username }}"

- name: Deploy settings.local.json (only if not present)
  ansible.builtin.template:
    src: settings.local.json.j2
    dest: "/home/{{ username }}/.claude/settings.local.json"
    owner: "{{ username }}"
    mode: "0644"
    force: false
  become: true
  become_user: "{{ username }}"

- name: Install Claude Code plugins
  ansible.builtin.shell: |
    /home/{{ username }}/.local/bin/claude plugins install {{ item }}
  loop: "{{ claude_plugins }}"
  become: true
  become_user: "{{ username }}"
  changed_when: false
```

Note: `settings.local.json` uses `force: false` so it doesn't overwrite accumulated permissions on re-runs.

**Step 7: Add desktop_wm var for the ThinkPad**

Add to `host_vars/thinkpad-x1.yml`:

```yaml
desktop_wm: i3wm
```

**Step 8: Commit**

```bash
cd ~/.infra
git add roles/claude-code/ host_vars/thinkpad-x1.yml
git commit -m "role: claude-code with install, configs, and plugins"
```

---

### Task 16: Create the custom-scripts role

**Files:**
- Create: `~/.infra/roles/custom-scripts/tasks/main.yml`
- Create: `~/.infra/roles/custom-scripts/files/sudo-askpass`
- Create: `~/.infra/roles/custom-scripts/files/run-claude`

Note: `auto-rotate` is device-specific and belongs in the `accelerometer` role, not here.

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/custom-scripts/{tasks,files}
```

**Step 2: Copy scripts**

`files/sudo-askpass`:
```sh
#!/bin/sh
rofi -dmenu -password -no-fixed-num-lines -p "sudo password"
```

`files/run-claude`:
```sh
#!/bin/sh
script="/tmp/claude-pending.sh"
if [ -f "$script" ]; then
    echo "Running:"
    cat "$script"
    echo ""
    sudo sh "$script"
    rm "$script"
else
    echo "No pending commands."
fi
```

**Step 3: Write `tasks/main.yml`**

```yaml
- name: Ensure ~/.local/bin exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.local/bin"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"

- name: Deploy custom scripts
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/home/{{ username }}/.local/bin/{{ item }}"
    owner: "{{ username }}"
    mode: "0755"
  loop:
    - sudo-askpass
    - run-claude
  become: true
  become_user: "{{ username }}"
```

**Step 4: Commit**

```bash
cd ~/.infra
git add roles/custom-scripts/
git commit -m "role: custom-scripts (sudo-askpass, run-claude)"
```

---

### Task 17: Create the docker role

**Files:**
- Create: `~/.infra/roles/docker/tasks/main.yml`
- Create: `~/.infra/roles/docker/tasks/archlinux.yml`
- Create: `~/.infra/roles/docker/tasks/debian.yml`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/docker/tasks
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Include distro-specific docker install
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"

- name: Add user to docker group
  ansible.builtin.user:
    name: "{{ username }}"
    groups: docker
    append: true

- name: Enable and start docker
  ansible.builtin.systemd:
    name: docker
    enabled: true
    state: started
```

**Step 3: Write `tasks/archlinux.yml`**

```yaml
- name: Install docker (Arch)
  community.general.pacman:
    name:
      - docker
      - docker-compose
    state: present
```

**Step 4: Write `tasks/debian.yml`**

```yaml
- name: Install docker prerequisites (Debian)
  ansible.builtin.apt:
    name:
      - ca-certificates
      - curl
      - gnupg
    state: present

- name: Add Docker GPG key
  ansible.builtin.shell: |
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  args:
    creates: /etc/apt/keyrings/docker.asc

- name: Add Docker apt repository
  ansible.builtin.apt_repository:
    repo: "deb [arch={{ ansible_architecture | regex_replace('x86_64', 'amd64') }} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian {{ ansible_distribution_release }} stable"
    state: present

- name: Install docker (Debian)
  ansible.builtin.apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
    state: present
    update_cache: true
```

**Step 5: Commit**

```bash
cd ~/.infra
git add roles/docker/
git commit -m "role: docker with multi-distro install"
```

---

### Task 18: Create the docker-stacks role and example media stack

**Files:**
- Create: `~/.infra/roles/docker-stacks/tasks/main.yml`
- Create: `~/.infra/roles/docker-stacks/handlers/main.yml`
- Create: `~/.infra/stacks/media/docker-compose.yml`
- Create: `~/.infra/stacks/media/.env.j2`

**Step 1: Create structure**

```bash
mkdir -p ~/.infra/roles/docker-stacks/{tasks,handlers}
mkdir -p ~/.infra/stacks/media
```

**Step 2: Write `roles/docker-stacks/tasks/main.yml`**

```yaml
- name: Create stack directory
  ansible.builtin.file:
    path: "/opt/docker/{{ stack }}"
    state: directory
    owner: "{{ username }}"
    group: "{{ username }}"
    mode: "0755"

- name: Deploy docker-compose.yml
  ansible.builtin.copy:
    src: "{{ playbook_dir }}/stacks/{{ stack }}/docker-compose.yml"
    dest: "/opt/docker/{{ stack }}/docker-compose.yml"
    owner: "{{ username }}"
    mode: "0644"
  notify: restart stack

- name: Template .env file
  ansible.builtin.template:
    src: "{{ playbook_dir }}/stacks/{{ stack }}/.env.j2"
    dest: "/opt/docker/{{ stack }}/.env"
    owner: "{{ username }}"
    mode: "0600"
  notify: restart stack

- name: Start stack
  community.docker.docker_compose_v2:
    project_src: "/opt/docker/{{ stack }}"
    state: present
```

**Step 3: Write `roles/docker-stacks/handlers/main.yml`**

```yaml
- name: restart stack
  community.docker.docker_compose_v2:
    project_src: "/opt/docker/{{ stack }}"
    state: restarted
```

**Step 4: Write `stacks/media/docker-compose.yml`** (simple example)

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    ports:
      - "8096:8096"
    volumes:
      - ./config/jellyfin:/config
      - /mnt/media:/media
    env_file: .env
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    ports:
      - "8989:8989"
    volumes:
      - ./config/sonarr:/config
      - /mnt/media:/media
    env_file: .env
    restart: unless-stopped
```

**Step 5: Write `stacks/media/.env.j2`**

```
TZ={{ timezone }}
PUID=1000
PGID=1000
```

You'll add API keys from vault later as you populate your real stacks.

**Step 6: Commit**

```bash
cd ~/.infra
git add roles/docker-stacks/ stacks/
git commit -m "role: docker-stacks with example media compose"
```

---

### Task 19: Create the tailscale role

**Files:**
- Create: `~/.infra/roles/tailscale/tasks/main.yml`
- Create: `~/.infra/roles/tailscale/tasks/archlinux.yml`
- Create: `~/.infra/roles/tailscale/tasks/debian.yml`

**Step 1: Create role structure**

```bash
mkdir -p ~/.infra/roles/tailscale/tasks
```

**Step 2: Write `tasks/main.yml`**

```yaml
- name: Include distro-specific install
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"

- name: Enable and start tailscaled
  ansible.builtin.systemd:
    name: tailscaled
    enabled: true
    state: started
```

**Step 3: Write `tasks/archlinux.yml`**

```yaml
- name: Install tailscale (Arch)
  community.general.pacman:
    name: tailscale
    state: present
```

**Step 4: Write `tasks/debian.yml`**

```yaml
- name: Install tailscale (Debian)
  ansible.builtin.shell: |
    curl -fsSL https://tailscale.com/install.sh | sh
  args:
    creates: /usr/bin/tailscale
```

**Step 5: Commit**

```bash
cd ~/.infra
git add roles/tailscale/
git commit -m "role: tailscale with multi-distro install"
```

---

### Task 20: Create device-specific roles (fingerprint, tlp, accelerometer, wwan)

These four roles are all tagged `thinkpad-x1` and use variables from `host_vars/thinkpad-x1.yml`.

**Files:**
- Create: `~/.infra/roles/fingerprint/tasks/main.yml`
- Create: `~/.infra/roles/tlp/tasks/main.yml`
- Create: `~/.infra/roles/tlp/templates/01-thinkpad.conf.j2`
- Create: `~/.infra/roles/accelerometer/tasks/main.yml`
- Create: `~/.infra/roles/accelerometer/templates/auto-rotate.j2`
- Create: `~/.infra/roles/wwan/tasks/main.yml`

**Step 1: Create all role structures**

```bash
mkdir -p ~/.infra/roles/fingerprint/tasks
mkdir -p ~/.infra/roles/tlp/{tasks,templates}
mkdir -p ~/.infra/roles/accelerometer/{tasks,templates}
mkdir -p ~/.infra/roles/wwan/tasks
```

**Step 2: Write `roles/fingerprint/tasks/main.yml`**

```yaml
- name: Install fprintd
  ansible.builtin.package:
    name: fprintd
    state: present

- name: Ensure pam_fprintd is in system-auth
  ansible.builtin.lineinfile:
    path: /etc/pam.d/system-auth
    insertafter: '^auth.*pam_unix'
    line: 'auth      sufficient pam_fprintd.so'
    state: present
```

**Step 3: Write `roles/tlp/templates/01-thinkpad.conf.j2`**

```
START_CHARGE_THRESH_BAT0={{ tlp_start_charge }}
STOP_CHARGE_THRESH_BAT0={{ tlp_stop_charge }}
```

**Step 4: Write `roles/tlp/tasks/main.yml`**

```yaml
- name: Install TLP
  ansible.builtin.package:
    name:
      - tlp
      - tlp-rdw
    state: present

- name: Deploy TLP config
  ansible.builtin.template:
    src: 01-thinkpad.conf.j2
    dest: /etc/tlp.d/01-thinkpad.conf
    mode: "0644"
  notify: restart tlp

- name: Enable TLP
  ansible.builtin.systemd:
    name: tlp
    enabled: true
    state: started

- name: Mask conflicting rfkill socket
  ansible.builtin.systemd:
    name: systemd-rfkill.socket
    masked: true
```

Add handler file `roles/tlp/handlers/main.yml`:

```yaml
- name: restart tlp
  ansible.builtin.systemd:
    name: tlp
    state: restarted
```

**Step 5: Write `roles/accelerometer/templates/auto-rotate.j2`**

```bash
#!/bin/bash
# Auto-rotate screen and touch inputs based on accelerometer
# Requires: iio-sensor-proxy, xrandr, xinput

SCREEN="{{ accelerometer_screen }}"
TOUCH_DEVICES=({% for dev in accelerometer_touch_devices %}"{{ dev }}" {% endfor %})

rotate_screen() {
    local orientation="$1"
    local xrandr_rot matrix

    case "$orientation" in
        normal)    xrandr_rot="normal";  matrix="1 0 0 0 1 0 0 0 1" ;;
        left-up)   xrandr_rot="left";    matrix="0 -1 1 1 0 0 0 0 1" ;;
        right-up)  xrandr_rot="right";   matrix="0 1 0 -1 0 1 0 0 1" ;;
        bottom-up) xrandr_rot="inverted"; matrix="-1 0 1 0 -1 1 0 0 1" ;;
        *) return ;;
    esac

    xrandr --output "$SCREEN" --rotate "$xrandr_rot"
    for device in "${TOUCH_DEVICES[@]}"; do
        xinput set-prop "$device" "Coordinate Transformation Matrix" $matrix 2>/dev/null
    done
}

monitor-sensor | while read -r line; do
    if [[ "$line" =~ "Accelerometer orientation changed:" ]]; then
        orientation="${line##*: }"
        rotate_screen "$orientation"
    fi
done
```

**Step 6: Write `roles/accelerometer/tasks/main.yml`**

```yaml
- name: Install iio-sensor-proxy
  ansible.builtin.package:
    name: iio-sensor-proxy
    state: present

- name: Deploy auto-rotate script
  ansible.builtin.template:
    src: auto-rotate.j2
    dest: "/home/{{ username }}/.local/bin/auto-rotate"
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"
```

**Step 7: Write `roles/wwan/tasks/main.yml`**

```yaml
- name: Install ModemManager
  ansible.builtin.package:
    name: modemmanager
    state: present

- name: Enable ModemManager
  ansible.builtin.systemd:
    name: ModemManager
    enabled: true
    state: started

- name: Create FCC unlock directory
  ansible.builtin.file:
    path: /etc/ModemManager/fcc-unlock.d
    state: directory
    mode: "0755"

- name: Create FCC unlock symlink
  ansible.builtin.file:
    src: /usr/share/ModemManager/fcc-unlock.available.d/{{ wwan_fcc_unlock_vid }}:{{ wwan_fcc_unlock_pid }}
    dest: /etc/ModemManager/fcc-unlock.d/{{ wwan_fcc_unlock_vid }}:{{ wwan_fcc_unlock_pid }}
    state: link
```

**Step 8: Commit**

```bash
cd ~/.infra
mkdir -p ~/.infra/roles/tlp/handlers
# (create the handler file too)
git add roles/fingerprint/ roles/tlp/ roles/accelerometer/ roles/wwan/
git commit -m "roles: device-specific (fingerprint, tlp, accelerometer, wwan)"
```

---

### Task 21: Move design docs into the repo and do end-to-end dry run

**Files:**
- Move: `~/docs/plans/*.md` → `~/.infra/docs/plans/`

**Step 1: Move design docs**

```bash
mkdir -p ~/.infra/docs/plans
cp ~/docs/plans/2025-02-12-ansible-config-empire-design.md ~/.infra/docs/plans/
cp ~/docs/plans/2025-02-12-ansible-config-empire-plan.md ~/.infra/docs/plans/
```

**Step 2: Full dry run**

```bash
cd ~/.infra
ansible-playbook site.yml --tags common,desktop,dev,thinkpad-x1 --check --diff
```

Expected: All tasks show as "ok" or "changed" (check mode). No errors.

**Step 3: Full real run (on this machine)**

```bash
cd ~/.infra
ansible-playbook site.yml --tags common,desktop,dev,thinkpad-x1
```

Expected: Most tasks "ok" since everything is already installed/configured. Some may show "changed" for newly managed configs.

**Step 4: Idempotency check — run again**

```bash
ansible-playbook site.yml --tags common,desktop,dev,thinkpad-x1
```

Expected: Zero "changed" tasks. Everything "ok".

**Step 5: Commit everything and push**

```bash
cd ~/.infra
git add -A
git commit -m "docs: add design and implementation plan"
```

---

### Task 22: Create GitHub repo and push

**Step 1: Create public repo on GitHub**

```bash
cd ~/.infra
gh repo create mate-vasarhelyi/infra --public --source=. --push
```

**Step 2: Verify**

```bash
gh repo view mate-vasarhelyi/infra --web
```

---

### Task 23: Clean up old dotfiles bare repo (optional, after verifying everything works)

This is the migration cutover. Only do this after confirming the Ansible repo handles everything.

**Step 1: Verify all old dotfiles configs are managed by Ansible**

Check that `~/.zshrc`, `~/.config/i3/config`, `~/.config/kitty/kitty.conf`, `~/.bashrc` are all deployed correctly by the new roles.

**Step 2: Remove the bare dotfiles repo**

```bash
rm -rf ~/.dotfiles
```

**Step 3: Remove the dotfiles alias from zshrc template**

The `infra` alias in the zsh template already replaces it.

**Step 4: Update CLAUDE.md template**

Make sure the CLAUDE.md.j2 template no longer references the old dotfiles bare repo.
