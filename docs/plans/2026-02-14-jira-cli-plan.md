# Jira CLI Role Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an Ansible role that installs jira-cli and configures it with Atlassian Cloud authentication from vault.

**Architecture:** New `jira-cli` role with multi-distro dispatch (Arch via AUR yay, Debian via binary release). Config templated to `~/.config/.jira/.config.yml`. API token exported in zshrc.

**Tech Stack:** Ansible, jira-cli, yay (AUR), GitHub releases

---

### Task 1: Add vault secrets and vars references

**Context:** Before the role can be written, the secrets it references must exist in vault and vars. This follows the existing pattern where `vault_*` vars are defined in `vault.yml` and referenced without prefix in `vars.yml`.

**Files:**
- Modify: `group_vars/all/vault.yml`
- Modify: `group_vars/all/vars.yml`

**Step 1: Add vault variables**

```bash
ansible-vault edit group_vars/all/vault.yml
```

Add these lines (user provides actual values):

```yaml
vault_jira_api_token: REPLACE_ME
vault_jira_server: https://YOURORG.atlassian.net
vault_jira_login: you@example.com
```

**Step 2: Add vars references**

In `group_vars/all/vars.yml`, append:

```yaml
jira_api_token: "{{ vault_jira_api_token }}"
jira_server: "{{ vault_jira_server }}"
jira_login: "{{ vault_jira_login }}"
```

**Step 3: Commit**

```bash
git add group_vars/all/vars.yml group_vars/all/vault.yml
git commit -m "add jira-cli vault secrets and vars references"
```

---

### Task 2: Create jira-cli role with distro-specific installation

**Context:** The role installs jira-cli. On Arch, it uses yay (already available via base-packages role). On Debian, it downloads the binary release from GitHub. Follows the multi-distro dispatch pattern from CLAUDE.md.

**Files:**
- Create: `roles/jira-cli/tasks/main.yml`
- Create: `roles/jira-cli/tasks/archlinux.yml`
- Create: `roles/jira-cli/tasks/debian.yml`

**Step 1: Create `roles/jira-cli/tasks/main.yml`**

```yaml
- name: Include distro-specific tasks
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

**Step 2: Create `roles/jira-cli/tasks/archlinux.yml`**

```yaml
- name: Install jira-cli from AUR
  ansible.builtin.command: yay -S --noconfirm --needed jira-cli
  become: true
  become_user: "{{ username }}"
  register: yay_result
  changed_when: "'there is nothing to do' not in yay_result.stdout"
```

Note: Uses `yay` which is installed by the `base-packages` role (runs before `jira-cli` in site.yml under `common` tag). The `--needed` flag makes it idempotent.

**Step 3: Create `roles/jira-cli/tasks/debian.yml`**

Use the binary download pattern from the fonts/debian role:

```yaml
- name: Install jira-cli from GitHub release
  ansible.builtin.shell: |
    cd /tmp
    curl -fLo jira.tar.gz https://github.com/ankitpokhrel/jira-cli/releases/latest/download/jira_{{ jira_cli_version }}_linux_{{ jira_cli_arch }}.tar.gz
    tar -xzf jira.tar.gz
    install -m 0755 bin/jira /usr/local/bin/jira
    rm -rf jira.tar.gz bin/
  args:
    creates: /usr/local/bin/jira
```

**Step 4: Create `roles/jira-cli/defaults/main.yml`**

```yaml
jira_cli_version: "1.7.0"
jira_cli_arch: "{{ ansible_architecture | regex_replace('x86_64', 'x86_64') | regex_replace('aarch64', 'arm64') }}"
jira_project_key: ""
jira_project_type: classic
```

**Step 5: Commit**

```bash
git add roles/jira-cli/
git commit -m "add jira-cli role with distro-specific installation"
```

---

### Task 3: Add jira-cli config template and auth env var

**Context:** jira-cli reads its config from `~/.config/.jira/.config.yml` and authenticates via the `JIRA_API_TOKEN` env var. The config file is templated from vault vars. The env var export is added to zshrc.j2 (same pattern as SUDO_ASKPASS).

**Files:**
- Create: `roles/jira-cli/templates/config.yml.j2`
- Modify: `roles/jira-cli/tasks/main.yml` (add config deployment tasks)
- Modify: `roles/zsh/templates/zshrc.j2` (add JIRA_API_TOKEN export)

**Step 1: Create `roles/jira-cli/templates/config.yml.j2`**

```yaml
installation: Cloud
server: {{ jira_server }}
login: {{ jira_login }}
{% if jira_project_key %}
project:
    key: {{ jira_project_key }}
    type: {{ jira_project_type }}
{% endif %}
```

Note: Board and issue type fields are omitted — they require API discovery. User can run `jira init` after first deploy or add them to the template later.

**Step 2: Add config deployment to `roles/jira-cli/tasks/main.yml`**

Append after the include_tasks line:

```yaml
- name: Ensure jira config directory exists
  ansible.builtin.file:
    path: "/home/{{ username }}/.config/.jira"
    state: directory
    owner: "{{ username }}"
    mode: "0755"
  become: true
  become_user: "{{ username }}"

- name: Deploy jira-cli config
  ansible.builtin.template:
    src: config.yml.j2
    dest: "/home/{{ username }}/.config/.jira/.config.yml"
    owner: "{{ username }}"
    mode: "0600"
  become: true
  become_user: "{{ username }}"
  when: jira_server is defined
  no_log: true
```

**Step 3: Add JIRA_API_TOKEN to `roles/zsh/templates/zshrc.j2`**

After the `# SUDO_ASKPASS` block (line 15), add:

```
# Jira CLI
{% if jira_api_token is defined %}
export JIRA_API_TOKEN="{{ jira_api_token }}"
{% endif %}
```

**Step 4: Commit**

```bash
git add roles/jira-cli/templates/ roles/jira-cli/tasks/ roles/zsh/templates/zshrc.j2
git commit -m "add jira-cli config template and auth env var to zshrc"
```

---

### Task 4: Register role in site.yml and verify

**Context:** New roles must be added to `site.yml` with appropriate tags (per CLAUDE.md). The jira-cli role goes under `common` tag, after `claude-code` (developer tooling cluster).

**Files:**
- Modify: `site.yml`

**Step 1: Add role to site.yml**

After the `claude-code` line (line 27), add:

```yaml
    - { role: jira-cli,       tags: [common] }
```

**Step 2: Verify syntax**

```bash
ansible-playbook site.yml --syntax-check
```

Expected: No errors.

**Step 3: Run lint**

```bash
ansible-lint site.yml
```

Expected: Clean or only pre-existing warnings.

**Step 4: Commit**

```bash
git add site.yml
git commit -m "register jira-cli role in site.yml under common tag"
```

---

### Task 5: Add vault secrets interactively

**Context:** The actual vault values need to be populated. This is a manual step — the user provides their Atlassian API token, server URL, and login email. This task is done outside the worktree, on the main repo.

**Step 1: Edit vault**

This is interactive and requires the vault password. Write commands to `/tmp/claude-pending.sh` for user to run:

```bash
cd ~/.infra
ansible-vault edit group_vars/all/vault.yml
```

User adds their actual values for `vault_jira_api_token`, `vault_jira_server`, `vault_jira_login`.

**Step 2: Commit vault changes**

```bash
git add group_vars/all/vault.yml
git commit -m "add jira-cli secrets to vault"
```

Note: This commit happens on main (vault changes are sensitive, not suitable for feature branch PRs).
