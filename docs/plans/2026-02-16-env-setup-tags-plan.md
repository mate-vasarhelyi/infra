# env/setup Tag Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the `common` tag into `env` (configure existing user) and `setup` (create user + configure), with `target_user` auto-detecting the logged-in user.

**Architecture:** Introduce `target_user` variable (defaults to `ansible_user_id`) used by all env/setup roles. Keep `username` for desktop/thinkpad/media roles. Replace `common` tag with `env` + `setup` in `site.yml`.

**Tech Stack:** Ansible, Jinja2 templates

---

### Task 1: Add `target_user` variable

**Files:**
- Modify: `group_vars/all/vars.yml:1`

**Step 1: Add target_user variable**

Add `target_user` as the first line in `group_vars/all/vars.yml`:

```yaml
target_user: "{{ ansible_user_id }}"
username: mate
```

`username` stays — it's still used by desktop/thinkpad/media roles.

**Step 2: Verify syntax**

Run: `ansible-playbook site.yml --syntax-check`
Expected: `playbook: site.yml` (no errors)

**Step 3: Commit**

```bash
git add group_vars/all/vars.yml
git commit -m "feat: add target_user variable defaulting to ansible_user_id"
```

---

### Task 2: Update site.yml tags

**Files:**
- Modify: `site.yml:19-47`

**Step 1: Replace common tag with env/setup**

Replace the roles section with:

```yaml
  roles:
    # setup = create user (new systems only)
    - { role: user-setup,      tags: [setup] }

    # env = packages + user config (works standalone or after setup)
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

**Step 2: Verify tags are correct**

Run: `ansible-playbook site.yml --list-tasks --tags env`
Expected: Lists all env roles (base-packages through custom-scripts), NOT user-setup.

Run: `ansible-playbook site.yml --list-tasks --tags setup`
Expected: Lists user-setup + all env roles.

**Step 3: Commit**

```bash
git add site.yml
git commit -m "feat: replace common tag with env/setup split"
```

---

### Task 3: Migrate user-setup role to target_user

**Files:**
- Modify: `roles/user-setup/tasks/main.yml:11`

**Step 1: Replace username with target_user**

Change line 11 from `name: "{{ username }}"` to `name: "{{ target_user }}"`:

```yaml
- name: Ensure user exists
  ansible.builtin.user:
    name: "{{ target_user }}"
    password: "{{ user_password | password_hash('sha512') }}"
    shell: /usr/bin/bash
    create_home: true
    groups: "{{ admin_group }}"
    append: true
    update_password: on_create
```

**Step 2: Verify syntax**

Run: `ansible-playbook site.yml --syntax-check`
Expected: no errors

**Step 3: Commit**

```bash
git add roles/user-setup/tasks/main.yml
git commit -m "feat(user-setup): use target_user variable"
```

---

### Task 4: Migrate zsh role to target_user

**Files:**
- Modify: `roles/zsh/tasks/main.yml` — all `{{ username }}` → `{{ target_user }}`
- Modify: `roles/zsh/templates/zshrc.j2:8` — `{{ username }}` → `{{ target_user }}`

**Step 1: Update tasks/main.yml**

Replace all `{{ username }}` with `{{ target_user }}` in `roles/zsh/tasks/main.yml`:

```yaml
- name: Install zsh
  ansible.builtin.package:
    name: zsh
    state: present

- name: Set zsh as default shell
  ansible.builtin.user:
    name: "{{ target_user }}"
    shell: /usr/bin/zsh

- name: Deploy .zshrc
  ansible.builtin.template:
    src: zshrc.j2
    dest: "/home/{{ target_user }}/.zshrc"
    owner: "{{ target_user }}"
    mode: "0644"
  become: true
  become_user: "{{ target_user }}"
```

**Step 2: Update templates/zshrc.j2 line 8**

Change:
```
zstyle :compinstall filename '/home/{{ username }}/.zshrc'
```
To:
```
zstyle :compinstall filename '/home/{{ target_user }}/.zshrc'
```

**Step 3: Verify syntax**

Run: `ansible-playbook site.yml --syntax-check`
Expected: no errors

**Step 4: Commit**

```bash
git add roles/zsh/
git commit -m "feat(zsh): use target_user variable"
```

---

### Task 5: Migrate git role to target_user

**Files:**
- Modify: `roles/git/tasks/main.yml` — all `{{ username }}` → `{{ target_user }}`

**Step 1: Update tasks/main.yml**

Replace all `{{ username }}` with `{{ target_user }}` (lines 10, 13, 17, 19, 22, 27, 28, 31):

```yaml
- name: Install git
  ansible.builtin.package:
    name: git
    state: present

- name: Deploy .gitconfig
  ansible.builtin.template:
    src: gitconfig.j2
    dest: "/home/{{ target_user }}/.gitconfig"
    owner: "{{ target_user }}"
    mode: "0644"
  become: true
  become_user: "{{ target_user }}"

- name: Ensure gh config directory exists
  ansible.builtin.file:
    path: "/home/{{ target_user }}/.config/gh"
    state: directory
    owner: "{{ target_user }}"
    mode: "0755"
  become: true
  become_user: "{{ target_user }}"

- name: Deploy gh hosts.yml
  ansible.builtin.template:
    src: gh_hosts.yml.j2
    dest: "/home/{{ target_user }}/.config/gh/hosts.yml"
    owner: "{{ target_user }}"
    mode: "0600"
  become: true
  become_user: "{{ target_user }}"
  when: github_token != "replace_me"
```

**Step 2: Verify syntax**

Run: `ansible-playbook site.yml --syntax-check`
Expected: no errors

**Step 3: Commit**

```bash
git add roles/git/
git commit -m "feat(git): use target_user variable"
```

---

### Task 6: Migrate ssh role to target_user

**Files:**
- Modify: `roles/ssh/tasks/main.yml` — all `{{ username }}` → `{{ target_user }}`

**Step 1: Update tasks/main.yml**

Replace all `{{ username }}` with `{{ target_user }}`:

```yaml
- name: Ensure .ssh directory exists
  ansible.builtin.file:
    path: "/home/{{ target_user }}/.ssh"
    state: directory
    owner: "{{ target_user }}"
    mode: "0700"

- name: Deploy SSH private key from vault
  ansible.builtin.copy:
    content: "{{ vault_ssh_private_key }}"
    dest: "/home/{{ target_user }}/.ssh/id_ed25519"
    owner: "{{ target_user }}"
    mode: "0600"
  when: vault_ssh_private_key is defined
  no_log: true

- name: Deploy SSH public key from vault
  ansible.builtin.copy:
    content: "{{ vault_ssh_public_key }}"
    dest: "/home/{{ target_user }}/.ssh/id_ed25519.pub"
    owner: "{{ target_user }}"
    mode: "0644"
  when: vault_ssh_public_key is defined
```

**Step 2: Commit**

```bash
git add roles/ssh/
git commit -m "feat(ssh): use target_user variable"
```

---

### Task 7: Migrate claude-code role to target_user

**Files:**
- Modify: `roles/claude-code/tasks/main.yml` — all `{{ username }}` → `{{ target_user }}`

**Step 1: Update tasks/main.yml**

Replace all `{{ username }}` with `{{ target_user }}` (lines 3, 6, 8, 12, 17, 19, 22, 27, 28, 31, 36, 37, 41, 47, 48, 51, 56, 57, 61, 65, 66, 69):

```yaml
- name: Install Claude Code via official script
  ansible.builtin.shell: |
    export HOME="/home/{{ target_user }}"
    curl -fsSL https://claude.ai/install.sh | bash
  args:
    creates: "/home/{{ target_user }}/.local/bin/claude"
  become: true
  become_user: "{{ target_user }}"

- name: Check if Claude Code binary exists
  ansible.builtin.stat:
    path: "/home/{{ target_user }}/.local/bin/claude"
  register: claude_binary

- name: Ensure ~/.claude directory exists
  ansible.builtin.file:
    path: "/home/{{ target_user }}/.claude"
    state: directory
    owner: "{{ target_user }}"
    mode: "0755"
  become: true
  become_user: "{{ target_user }}"

- name: Deploy CLAUDE.md
  ansible.builtin.template:
    src: CLAUDE.md.j2
    dest: "/home/{{ target_user }}/.claude/CLAUDE.md"
    owner: "{{ target_user }}"
    mode: "0644"
  become: true
  become_user: "{{ target_user }}"

- name: Deploy OAuth credentials (only if not present)
  ansible.builtin.template:
    src: credentials.json.j2
    dest: "/home/{{ target_user }}/.claude/.credentials.json"
    owner: "{{ target_user }}"
    mode: "0600"
    force: false
  become: true
  become_user: "{{ target_user }}"
  no_log: true

- name: Deploy settings.json
  ansible.builtin.copy:
    src: settings.json
    dest: "/home/{{ target_user }}/.claude/settings.json"
    owner: "{{ target_user }}"
    mode: "0644"
  become: true
  become_user: "{{ target_user }}"

- name: Deploy settings.local.json (only if not present)
  ansible.builtin.template:
    src: settings.local.json.j2
    dest: "/home/{{ target_user }}/.claude/settings.local.json"
    owner: "{{ target_user }}"
    mode: "0644"
    force: false
  become: true
  become_user: "{{ target_user }}"

- name: Install Claude Code plugins
  ansible.builtin.shell: |
    export HOME="/home/{{ target_user }}"
    /home/{{ target_user }}/.local/bin/claude plugins install {{ item }}
  loop: "{{ claude_plugins }}"
  become: true
  become_user: "{{ target_user }}"
  changed_when: false
  failed_when: false
  when: claude_binary.stat.exists
```

**Step 2: Commit**

```bash
git add roles/claude-code/
git commit -m "feat(claude-code): use target_user variable"
```

---

### Task 8: Migrate jira-cli role to target_user

**Files:**
- Modify: `roles/jira-cli/tasks/main.yml` — all `{{ username }}` → `{{ target_user }}`

**Step 1: Update tasks/main.yml**

Replace all `{{ username }}` with `{{ target_user }}` (lines 13, 15, 18, 23, 24, 27):

```yaml
- name: Install jira-cli from GitHub release
  ansible.builtin.shell: |
    cd /tmp
    curl -fLo jira.tar.gz https://github.com/ankitpokhrel/jira-cli/releases/download/v{{ jira_cli_version }}/jira_{{ jira_cli_version }}_linux_{{ jira_cli_arch }}.tar.gz
    tar -xzf jira.tar.gz
    install -m 0755 jira_{{ jira_cli_version }}_linux_{{ jira_cli_arch }}/bin/jira /usr/local/bin/jira
    rm -rf jira.tar.gz jira_{{ jira_cli_version }}_linux_{{ jira_cli_arch }}/
  args:
    creates: /usr/local/bin/jira

- name: Ensure jira config directory exists
  ansible.builtin.file:
    path: "/home/{{ target_user }}/.config/.jira"
    state: directory
    owner: "{{ target_user }}"
    mode: "0755"
  become: true
  become_user: "{{ target_user }}"

- name: Deploy jira-cli config
  ansible.builtin.template:
    src: config.yml.j2
    dest: "/home/{{ target_user }}/.config/.jira/.config.yml"
    owner: "{{ target_user }}"
    mode: "0600"
  become: true
  become_user: "{{ target_user }}"
  when: jira_server is defined
  no_log: true
```

**Step 2: Commit**

```bash
git add roles/jira-cli/
git commit -m "feat(jira-cli): use target_user variable"
```

---

### Task 9: Migrate custom-scripts role to target_user

**Files:**
- Modify: `roles/custom-scripts/tasks/main.yml` — all `{{ username }}` → `{{ target_user }}`

**Step 1: Update tasks/main.yml**

```yaml
- name: Ensure ~/.local/bin exists
  ansible.builtin.file:
    path: "/home/{{ target_user }}/.local/bin"
    state: directory
    owner: "{{ target_user }}"
    mode: "0755"
  become: true
  become_user: "{{ target_user }}"

- name: Deploy custom scripts
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/home/{{ target_user }}/.local/bin/{{ item }}"
    owner: "{{ target_user }}"
    mode: "0755"
  loop:
    - sudo-askpass
    - run-claude
  become: true
  become_user: "{{ target_user }}"
```

**Step 2: Commit**

```bash
git add roles/custom-scripts/
git commit -m "feat(custom-scripts): use target_user variable"
```

---

### Task 10: Migrate docker role to target_user

**Files:**
- Modify: `roles/docker/tasks/main.yml:6`

**Step 1: Update tasks/main.yml line 6**

Change `name: "{{ username }}"` to `name: "{{ target_user }}"`:

```yaml
- name: Add user to docker group
  ansible.builtin.user:
    name: "{{ target_user }}"
    groups: docker
    append: true
```

**Step 2: Commit**

```bash
git add roles/docker/
git commit -m "feat(docker): use target_user variable"
```

---

### Task 11: Migrate base-packages role to target_user

**Files:**
- Modify: `roles/base-packages/tasks/archlinux.yml` — lines 24, 32: `{{ username }}` → `{{ target_user }}`

**Step 1: Update archlinux.yml**

Change `become_user: "{{ username }}"` to `become_user: "{{ target_user }}"` on lines 24 and 32 (yay clone and build tasks).

**Step 2: Commit**

```bash
git add roles/base-packages/
git commit -m "feat(base-packages): use target_user for yay build"
```

---

### Task 12: Update CLAUDE.md tags table and docs

**Files:**
- Modify: `CLAUDE.md:36-44` — tags table
- Modify: `CLAUDE.md:76` — config files section reference
- Modify: `CLAUDE.md:90` — file permissions section reference
- Modify: `CLAUDE.md:98` — gotchas section reference

**Step 1: Update tags table**

Replace lines 36-44:

```markdown
## Tags

| Tag | Roles |
|-----|-------|
| `env` | base-packages, zsh, git, starship, ssh, fonts, tailscale, claude-code, jira-cli, docker, custom-scripts |
| `setup` | user-setup + all `env` roles |
| `desktop` | i3, rofi, dunst, kitty, touchpad |
| `media` | docker-stacks |
| `thinkpad-x1` | fingerprint, tlp, accelerometer, wwan |

Combine: `--tags env,desktop`
```

**Step 2: Update config files section**

Change line 76 from:
```
- User configs (dotfiles): `templates/` with `.j2` extension, dest to `/home/{{ username }}/`
```
To:
```
- User configs (dotfiles): `templates/` with `.j2` extension, dest to `/home/{{ target_user }}/` (env/setup roles) or `/home/{{ username }}/` (desktop roles)
```

**Step 3: Update file permissions table**

Change owner column references from `{{ username }}` to `{{ target_user }}` for env roles:

```markdown
| Type | Owner | Mode |
|------|-------|------|
| User configs (env roles) | `{{ target_user }}` | `0644` |
| User configs (desktop roles) | `{{ username }}` | `0644` |
| Secrets (keys, tokens) | `{{ target_user }}` | `0600` |
| Scripts | `{{ target_user }}` | `0755` |
| System configs | root | `0644` |
```

**Step 4: Update gotchas**

Change line 98 from:
```
- `become: true` makes `ansible_env.HOME` resolve to `/root` — use `/home/{{ username }}/` in paths
```
To:
```
- `become: true` makes `ansible_env.HOME` resolve to `/root` — use `/home/{{ target_user }}/` (env/setup roles) or `/home/{{ username }}/` (desktop roles)
```

**Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for env/setup tag split"
```

---

### Task 13: End-to-end verification

**Step 1: Syntax check**

Run: `ansible-playbook site.yml --syntax-check`
Expected: `playbook: site.yml`

**Step 2: Verify env tag lists correct tasks**

Run: `ansible-playbook site.yml --list-tasks --tags env`
Expected: All env roles listed, user-setup NOT listed.

**Step 3: Verify setup tag lists correct tasks**

Run: `ansible-playbook site.yml --list-tasks --tags setup`
Expected: user-setup + all env roles listed.

**Step 4: Verify desktop tag is unchanged**

Run: `ansible-playbook site.yml --list-tasks --tags desktop`
Expected: i3, rofi, dunst, kitty, touchpad listed.

**Step 5: Verify no stale username references in env roles**

Run: `grep -r '{{ username }}' roles/zsh roles/git roles/ssh roles/claude-code roles/jira-cli roles/custom-scripts roles/docker roles/base-packages roles/user-setup`
Expected: No matches.

**Step 6: Verify username still used in desktop roles**

Run: `grep -r '{{ username }}' roles/i3 roles/rofi roles/dunst roles/kitty`
Expected: Matches present (these roles should still use `username`).

**Step 7: Dry run with env tag**

Run: `ansible-playbook site.yml --tags env --check --ask-vault-pass`
Expected: All tasks show ok/changed, no errors. `target_user` resolves to current user.
