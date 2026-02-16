# Remote Dev Role Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a `remote-dev` Ansible role that installs code-server and ttyd+zellij as systemd services for browser-based remote development.

**Architecture:** Single role with distro dispatch (Arch/Debian). Both tools installed natively (not Docker) with systemd units. No auth — network-level trust only.

**Tech Stack:** Ansible, systemd, code-server, ttyd, zellij

**Design note:** The design doc says code-server uses `community.general.pacman` on Arch, but code-server is AUR-only, not in official repos. We use the official install script on both distros instead — it's simpler and consistent.

---

### Task 1: Create role defaults

**Files:**
- Create: `roles/remote-dev/defaults/main.yml`

**Step 1: Create the defaults file**

```yaml
code_server_port: 8080
ttyd_port: 7681
ttyd_version: "1.7.7"
```

**Step 2: Commit**

```bash
git add roles/remote-dev/defaults/main.yml
git commit -m "feat(remote-dev): add role defaults"
```

---

### Task 2: Create systemd unit templates

**Files:**
- Create: `roles/remote-dev/templates/code-server.service.j2`
- Create: `roles/remote-dev/templates/ttyd.service.j2`

**Step 1: Create code-server systemd unit**

File: `roles/remote-dev/templates/code-server.service.j2`

```ini
[Unit]
Description=code-server
After=network.target

[Service]
Type=simple
User={{ target_user }}
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:{{ code_server_port }} --auth none /
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Step 2: Create ttyd systemd unit**

File: `roles/remote-dev/templates/ttyd.service.j2`

```ini
[Unit]
Description=ttyd - web terminal with zellij
After=network.target

[Service]
Type=simple
User={{ target_user }}
ExecStart=/usr/bin/ttyd -p {{ ttyd_port }} -W zellij
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Step 3: Commit**

```bash
git add roles/remote-dev/templates/
git commit -m "feat(remote-dev): add systemd unit templates"
```

---

### Task 3: Create handlers

**Files:**
- Create: `roles/remote-dev/handlers/main.yml`

**Step 1: Create handlers file**

```yaml
- name: Restart code-server
  ansible.builtin.systemd:
    name: code-server
    state: restarted
    daemon_reload: true

- name: Restart ttyd
  ansible.builtin.systemd:
    name: ttyd
    state: restarted
    daemon_reload: true
```

**Step 2: Commit**

```bash
git add roles/remote-dev/handlers/main.yml
git commit -m "feat(remote-dev): add restart handlers"
```

---

### Task 4: Create Debian install tasks

**Files:**
- Create: `roles/remote-dev/tasks/debian.yml`

**Step 1: Create Debian task file**

```yaml
- name: Install code-server via official script
  ansible.builtin.shell: curl -fsSL https://code-server.dev/install.sh | sh
  args:
    creates: /usr/bin/code-server

- name: Install ttyd from GitHub release
  ansible.builtin.shell: |
    curl -fLo /usr/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/{{ ttyd_version }}/ttyd.{{ ansible_architecture }}"
    chmod 0755 /usr/bin/ttyd
  args:
    creates: /usr/bin/ttyd
```

Notes:
- `creates:` makes both tasks idempotent — skips if binary already exists
- `ansible_architecture` resolves to `x86_64` or `aarch64`, matching ttyd release asset names
- Follows the same `shell` + `creates` pattern used by `roles/base-packages/tasks/archlinux.yml` for yay

**Step 2: Commit**

```bash
git add roles/remote-dev/tasks/debian.yml
git commit -m "feat(remote-dev): add Debian install tasks"
```

---

### Task 5: Create Arch install tasks

**Files:**
- Create: `roles/remote-dev/tasks/archlinux.yml`

**Step 1: Create Arch task file**

```yaml
- name: Install ttyd
  community.general.pacman:
    name: ttyd
    state: present

- name: Install code-server via official script
  ansible.builtin.shell: curl -fsSL https://code-server.dev/install.sh | sh
  args:
    creates: /usr/bin/code-server
```

Notes:
- `ttyd` is in the official Arch community repo — use pacman directly
- `code-server` is AUR-only, so we use the official install script (same as Debian)
- The install script detects Arch and installs the standalone version to `/usr/lib/code-server/` with symlink at `/usr/bin/code-server`

**Step 2: Commit**

```bash
git add roles/remote-dev/tasks/archlinux.yml
git commit -m "feat(remote-dev): add Arch install tasks"
```

---

### Task 6: Create main tasks (distro dispatch + systemd)

**Files:**
- Create: `roles/remote-dev/tasks/main.yml`

**Step 1: Create main task file**

```yaml
- name: Include distro-specific tasks
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"

- name: Deploy code-server systemd unit
  ansible.builtin.template:
    src: code-server.service.j2
    dest: /etc/systemd/system/code-server.service
    mode: "0644"
  notify: Restart code-server

- name: Deploy ttyd systemd unit
  ansible.builtin.template:
    src: ttyd.service.j2
    dest: /etc/systemd/system/ttyd.service
    mode: "0644"
  notify: Restart ttyd

- name: Enable and start code-server
  ansible.builtin.systemd:
    name: code-server
    enabled: true
    state: started
    daemon_reload: true

- name: Enable and start ttyd
  ansible.builtin.systemd:
    name: ttyd
    enabled: true
    state: started
    daemon_reload: true
```

Notes:
- Distro dispatch first (install binaries), then deploy units, then enable/start
- `notify` on template changes triggers restart handler only when the unit file changes
- `daemon_reload: true` on the enable/start tasks ensures systemd picks up new units on first run

**Step 2: Commit**

```bash
git add roles/remote-dev/tasks/main.yml
git commit -m "feat(remote-dev): add main tasks with distro dispatch"
```

---

### Task 7: Add role to site.yml

**Files:**
- Modify: `site.yml:44` (after the `# purpose` section)

**Step 1: Add remote-dev role**

Add after line 44 (`docker-stacks` role), before the `# device-specific` comment:

```yaml
    - { role: remote-dev,      tags: [remote-dev] }
```

The purpose section should now read:

```yaml
    # purpose
    - { role: docker-stacks,   tags: [media], vars: { stack: media } }
    - { role: remote-dev,      tags: [remote-dev] }
```

**Step 2: Commit**

```bash
git add site.yml
git commit -m "feat(remote-dev): add role to site.yml with remote-dev tag"
```

---

### Task 8: Test the role with --check

**Step 1: Run ansible-playbook in check mode**

```bash
ansible-playbook site.yml --tags remote-dev --check
```

Expected: Tasks should show "changed" status (since nothing is installed yet) but no errors. Verifies syntax and variable resolution.

**Step 2: If errors, fix and amend the relevant commit. If clean, proceed.**

---

### Task 9: Update CLAUDE.md tag table

**Files:**
- Modify: `CLAUDE.md` (tag table section)

**Step 1: Add remote-dev to the tag table**

Add a new row to the tag table:

```
| `remote-dev` | remote-dev |
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add remote-dev tag to CLAUDE.md"
```
