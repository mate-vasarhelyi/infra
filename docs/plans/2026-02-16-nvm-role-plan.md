# NVM Role Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an nvm role that installs Node Version Manager and LTS Node.js on all `env`-tagged systems.

**Architecture:** New `roles/nvm/` role installs nvm via the official curl script, then installs LTS Node. Shell integration is added to the existing zshrc template. The role is tagged `[env, setup]` in site.yml.

**Tech Stack:** Ansible, nvm (curl install script), zsh

---

### Task 1: Create nvm role defaults

**Files:**
- Create: `roles/nvm/defaults/main.yml`

**Step 1: Create the defaults file**

```yaml
nvm_version: "0.40.1"
```

**Step 2: Verify the file**

Run: `cat roles/nvm/defaults/main.yml`
Expected: shows the version variable

**Step 3: Commit**

```bash
git add roles/nvm/defaults/main.yml
git commit -m "feat(nvm): add role defaults with version pin"
```

---

### Task 2: Create nvm role tasks

**Files:**
- Create: `roles/nvm/tasks/main.yml`

**Context:** The install pattern follows `roles/claude-code/tasks/main.yml` — use `ansible.builtin.shell` with `become_user: "{{ target_user }}"` and `export HOME` to ensure the script installs to the correct home directory. Use `creates:` for idempotency.

For the LTS node install, source nvm first (it's a shell function, not a binary), then run `nvm install --lts`. Check idempotency by testing if `nvm ls --no-colors --no-alias | grep -q lts` succeeds.

**Step 1: Create the tasks file**

```yaml
- name: Install nvm via official script
  ansible.builtin.shell: |
    export HOME="/home/{{ target_user }}"
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v{{ nvm_version }}/install.sh" | bash
  args:
    creates: "/home/{{ target_user }}/.nvm/nvm.sh"
  become: true
  become_user: "{{ target_user }}"

- name: Install LTS Node.js
  ansible.builtin.shell: |
    export HOME="/home/{{ target_user }}"
    export NVM_DIR="/home/{{ target_user }}/.nvm"
    . "$NVM_DIR/nvm.sh"
    nvm install --lts
  args:
    creates: "/home/{{ target_user }}/.nvm/alias/lts/*"
  become: true
  become_user: "{{ target_user }}"
```

**Step 2: Syntax check**

Run: `ansible-playbook site.yml --syntax-check`
Expected: `playbook: site.yml` (will fail until Task 4 adds the role to site.yml — that's fine, just verify no YAML errors with `python3 -c "import yaml; yaml.safe_load(open('roles/nvm/tasks/main.yml'))"`)

**Step 3: Commit**

```bash
git add roles/nvm/tasks/main.yml
git commit -m "feat(nvm): add tasks for nvm + LTS node install"
```

---

### Task 3: Add nvm sourcing to zshrc template

**Files:**
- Modify: `roles/zsh/templates/zshrc.j2:22-23` (after the `# PATH` block, before `# Aliases`)

**Context:** nvm is a shell function loaded by sourcing `~/.nvm/nvm.sh`. Add a block that conditionally sources it if the file exists. Place it after PATH exports and before aliases.

**Step 1: Add nvm sourcing block**

Insert after line 23 (`export PATH="$HOME/.local/bin:$PATH"`) and before line 25 (`# Aliases`):

```
# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
```

The result should be:
```
# PATH
export PATH="$HOME/.local/bin:$PATH"

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# Aliases
```

**Step 2: Verify template syntax**

Run: `python3 -c "from jinja2 import Environment; Environment().parse(open('roles/zsh/templates/zshrc.j2').read()); print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add roles/zsh/templates/zshrc.j2
git commit -m "feat(nvm): add nvm sourcing to zshrc template"
```

---

### Task 4: Add nvm role to site.yml

**Files:**
- Modify: `site.yml:31` (after jira-cli, before docker — or anywhere in the env block)

**Step 1: Add the nvm role entry**

Add this line after the `jira-cli` entry (line 31) and before `docker` (line 32):

```yaml
    - { role: nvm,            tags: [env, setup] }
```

The env block should now read:
```yaml
    - { role: base-packages,   tags: [env, setup] }
    - { role: zsh,             tags: [env, setup] }
    - { role: git,             tags: [env, setup] }
    - { role: starship,        tags: [env, setup] }
    - { role: ssh,             tags: [env, setup] }
    - { role: fonts,           tags: [env, setup] }
    - { role: tailscale,       tags: [env, setup] }
    - { role: claude-code,     tags: [env, setup] }
    - { role: jira-cli,        tags: [env, setup] }
    - { role: nvm,             tags: [env, setup] }
    - { role: docker,          tags: [env, setup] }
    - { role: custom-scripts,  tags: [env, setup] }
```

**Step 2: Syntax check**

Run: `ansible-playbook site.yml --syntax-check`
Expected: `playbook: site.yml`

**Step 3: Commit**

```bash
git add site.yml
git commit -m "feat(nvm): add nvm role to site.yml with env/setup tags"
```

---

### Task 5: Update CLAUDE.md tags table

**Files:**
- Modify: `CLAUDE.md:39` (tags table, `env` row)

**Step 1: Update the env tag row**

Change line 39 from:
```
| `env` | base-packages, zsh, git, starship, ssh, fonts, tailscale, claude-code, jira-cli, docker, custom-scripts |
```
to:
```
| `env` | base-packages, zsh, git, starship, ssh, fonts, tailscale, claude-code, jira-cli, nvm, docker, custom-scripts |
```

**Step 2: Verify**

Run: `grep 'nvm' CLAUDE.md`
Expected: shows the updated tags table row

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add nvm to env tag in CLAUDE.md"
```

---

### Task 6: End-to-end verification

**Step 1: Full syntax check**

Run: `ansible-playbook site.yml --syntax-check`
Expected: `playbook: site.yml`

**Step 2: Verify tag assignment**

Run: `ansible-playbook site.yml --tags env --list-tasks 2>/dev/null | grep nvm`
Expected: shows nvm tasks listed under env tag

Run: `ansible-playbook site.yml --tags setup --list-tasks 2>/dev/null | grep nvm`
Expected: shows nvm tasks listed under setup tag

**Step 3: Verify zshrc template has nvm block**

Run: `grep -A3 '# NVM' roles/zsh/templates/zshrc.j2`
Expected: shows the NVM_DIR export and sourcing lines

**Step 4: Dry run (optional — requires become password)**

Run: `ansible-playbook site.yml --tags env --check --diff --ask-become-pass`
Expected: shows nvm tasks would run (may skip curl in check mode, that's fine)
