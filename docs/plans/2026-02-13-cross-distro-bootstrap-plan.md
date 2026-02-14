# Cross-Distro Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Ansible playbook work reliably on both Arch and Debian from a completely fresh machine.

**Architecture:** Create a `user-setup` role with distro dispatch to replace the hacky pre_tasks. Fix distro-specific package names across base-packages. Add missing APT repos for gh and kubectl on Debian. Make sudo-askpass work without rofi.

**Tech Stack:** Ansible, bash

---

### Task 1: Create `user-setup` role with distro dispatch

**Files:**
- Create: `roles/user-setup/tasks/main.yml`
- Create: `roles/user-setup/tasks/archlinux.yml`
- Create: `roles/user-setup/tasks/debian.yml`

**Step 1: Create `roles/user-setup/tasks/main.yml`**

This is the entry point. It installs sudo, dispatches to distro-specific tasks for passlib and admin group setup, then creates the user and configures sudoers.

```yaml
- name: Install sudo
  ansible.builtin.package:
    name: sudo
    state: present

- name: Include distro-specific setup
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"

- name: Ensure user exists
  ansible.builtin.user:
    name: "{{ username }}"
    password: "{{ user_password | password_hash('sha512') }}"
    shell: /usr/bin/bash
    create_home: true
    groups: "{{ admin_group }}"
    append: true
    update_password: on_create
```

**Step 2: Create `roles/user-setup/tasks/archlinux.yml`**

```yaml
- name: Install passlib (Arch)
  community.general.pacman:
    name: python-passlib
    state: present

- name: Set admin group
  ansible.builtin.set_fact:
    admin_group: wheel

- name: Enable sudo for wheel group
  ansible.builtin.lineinfile:
    path: /etc/sudoers
    regexp: '^# ?%wheel ALL=\(ALL:ALL\) ALL'
    line: '%wheel ALL=(ALL:ALL) ALL'
    validate: 'visudo -cf %s'
```

**Step 3: Create `roles/user-setup/tasks/debian.yml`**

```yaml
- name: Install passlib (Debian)
  ansible.builtin.apt:
    name: python3-passlib
    state: present
    update_cache: true

- name: Set admin group
  ansible.builtin.set_fact:
    admin_group: sudo

- name: Ensure sudo group has sudo privileges
  ansible.builtin.lineinfile:
    path: /etc/sudoers
    regexp: '^%sudo'
    line: '%sudo ALL=(ALL:ALL) ALL'
    validate: 'visudo -cf %s'
```

**Step 4: Commit**

```bash
git add roles/user-setup/
git commit -m "add user-setup role with distro dispatch for Arch and Debian"
```

---

### Task 2: Clean up `site.yml` — replace pre_tasks with user-setup role

**Files:**
- Modify: `site.yml`

**Step 1: Replace pre_tasks and add user-setup role**

Remove the entire pre_tasks block (lines 10-35 — the sudo install, user creation, and sudoers tasks). Keep only the facts gathering. Add `user-setup` as the first role.

The new `site.yml` should look like:

```yaml
- hosts: localhost
  connection: local
  become: true

  pre_tasks:
    - name: Gather facts
      ansible.builtin.setup:
      tags: always

  roles:
    # common
    - { role: user-setup,      tags: [common] }
    - { role: base-packages,   tags: [common] }
    - { role: zsh,             tags: [common] }
    - { role: git,             tags: [common] }
    - { role: starship,        tags: [common] }
    - { role: ssh,             tags: [common] }
    - { role: fonts,           tags: [common] }
    - { role: tailscale,       tags: [common] }
    - { role: claude-code,     tags: [common] }
    - { role: docker,          tags: [common] }
    - { role: custom-scripts,  tags: [common] }

    # desktop
    - { role: i3,              tags: [desktop] }
    - { role: rofi,            tags: [desktop] }
    - { role: dunst,           tags: [desktop] }
    - { role: kitty,           tags: [desktop] }
    - { role: touchpad,        tags: [desktop] }

    # purpose
    - { role: docker-stacks,   tags: [media], vars: { stack: media } }

    # device-specific
    - { role: fingerprint,     tags: [thinkpad-x1] }
    - { role: tlp,             tags: [thinkpad-x1] }
    - { role: accelerometer,   tags: [thinkpad-x1] }
    - { role: wwan,            tags: [thinkpad-x1] }
```

**Step 2: Commit**

```bash
git add site.yml
git commit -m "replace pre_tasks user setup with dedicated user-setup role"
```

---

### Task 3: Fix `openssh` package name for Debian

**Files:**
- Modify: `roles/base-packages/defaults/main.yml`

**Step 1: Move openssh and sudo out of shared list into distro-specific lists**

`openssh` is Arch-only. Debian needs `openssh-client`. `sudo` is now handled by `user-setup` role, remove it from base_packages.

New `defaults/main.yml`:

```yaml
base_packages:
  - curl
  - wget
  - htop
  - jq
  - tree
  - unzip
  - man-db

base_packages_archlinux:
  - ripgrep
  - fd
  - bat
  - base-devel
  - github-cli
  - kubectl
  - openssh

base_packages_debian:
  - ripgrep
  - fd-find
  - bat
  - build-essential
  - openssh-client
```

Note: `gh` removed from `base_packages_debian` — it will be installed separately after adding the APT repo (Task 4). `sudo` removed from shared list — handled by `user-setup` role.

**Step 2: Commit**

```bash
git add roles/base-packages/defaults/main.yml
git commit -m "fix openssh package name for Debian, remove sudo from base packages"
```

---

### Task 4: Fix `gh` CLI and `kubectl` install on Debian

**Files:**
- Modify: `roles/base-packages/tasks/debian.yml`

**Step 1: Add GitHub CLI APT repo and install gh separately. Fix kubectl to use stable channel.**

New `debian.yml`:

```yaml
- name: Install Debian-specific packages
  ansible.builtin.apt:
    name: "{{ base_packages_debian }}"
    state: present
    update_cache: true

- name: Add GitHub CLI GPG key
  ansible.builtin.shell: |
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  args:
    creates: /etc/apt/keyrings/githubcli-archive-keyring.gpg

- name: Add GitHub CLI APT repository
  ansible.builtin.apt_repository:
    repo: "deb [arch={{ ansible_architecture | regex_replace('x86_64', 'amd64') }} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
    state: present

- name: Install GitHub CLI
  ansible.builtin.apt:
    name: gh
    state: present
    update_cache: true

- name: Add Kubernetes GPG key
  ansible.builtin.shell: |
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  args:
    creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

- name: Add Kubernetes APT repository
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /"
    state: present

- name: Install kubectl
  ansible.builtin.apt:
    name: kubectl
    state: present
    update_cache: true
```

**Step 2: Commit**

```bash
git add roles/base-packages/tasks/debian.yml
git commit -m "add GitHub CLI APT repo on Debian, clean up kubectl install"
```

---

### Task 5: Make `sudo-askpass` work without rofi

**Files:**
- Modify: `roles/custom-scripts/files/sudo-askpass`

**Step 1: Update sudo-askpass to fall back to terminal prompt when rofi is not available**

```sh
#!/bin/sh
if command -v rofi >/dev/null 2>&1; then
    rofi -dmenu -password -no-fixed-num-lines -p "sudo password"
else
    echo "Password:" >&2
    read -rs pass
    echo "$pass"
fi
```

**Step 2: Commit**

```bash
git add roles/custom-scripts/files/sudo-askpass
git commit -m "sudo-askpass: fall back to terminal prompt when rofi is unavailable"
```

---

### Task 6: Update CLAUDE.md and tag table

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add `user-setup` to the common tag in the CLAUDE.md tag table**

Update the tag table row for `common` to include `user-setup` at the beginning:

```
| `common` | user-setup, base-packages, zsh, git, starship, ssh, fonts, tailscale, claude-code, docker, custom-scripts |
```

Also remove `server` tag row if still present since docker moved to common.

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "update CLAUDE.md tag table with user-setup role"
```

---

### Task 7: Test — dry run syntax check

**Step 1: Run ansible syntax check**

```bash
ansible-playbook site.yml --syntax-check
```

Expected: No errors.

**Step 2: Run with --check on localhost (Arch)**

```bash
ansible-playbook site.yml --tags common --check --diff
```

Expected: Shows what would change, no errors. Some tasks may show "skipped" due to check mode limitations.

**Step 3: Commit and push everything**

```bash
git push
```

---

### Task 8: Test on fresh Arch container

**Step 1: Nuke existing test CT and create a fresh one**

User does this in Proxmox.

**Step 2: Run bootstrap**

```bash
curl -fsSL https://api.github.com/repos/mate-vasarhelyi/infra/contents/bootstrap.sh -H "Accept: application/vnd.github.raw" | bash
```

**Step 3: Run playbook**

```bash
cd ~/.infra
ansible-playbook site.yml --tags common
```

Expected: Complete run with no failures. User `mate` created with password, sudo working, all packages installed.

**Step 4: Verify**

```bash
su - mate
sudo whoami  # should output: root
gst          # should run git status (alias works)
k version    # kubectl responds
```
