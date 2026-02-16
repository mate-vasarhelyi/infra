# Ansible Infrastructure

Configures machines from fresh install. Runs against localhost.

```
ansible-playbook site.yml --tags <tags> --ask-become-pass
```

- `become_method = su` (avoids fprintd PAM timeout with sudo)
- Vault password: `.vault-pass` (gitignored)
- Galaxy deps: `ansible-galaxy collection install -r requirements.yml`

## Layout

```
~/.infra/
├── site.yml              # Main playbook — all roles listed here
├── ansible.cfg           # become_method=su, vault_password_file
├── bootstrap.sh          # Fresh machine setup script
├── requirements.yml      # Galaxy collections (community.docker, community.general)
├── group_vars/all/
│   ├── vars.yml          # Shared variables (vault_ refs go here)
│   └── vault.yml         # Encrypted secrets (vault_ prefix)
├── host_vars/
│   └── localhost.yml     # Machine-specific vars (must match target hostname)
├── roles/<name>/
│   ├── tasks/main.yml    # Entry point — always present
│   ├── defaults/main.yml # Default variables (optional)
│   ├── templates/        # Jinja2 .j2 files (optional)
│   ├── files/            # Static files (optional)
│   └── handlers/main.yml # Handlers (optional)
└── stacks/<name>/        # Docker compose stacks
```

## Tags

| Tag | Roles |
|-----|-------|
| `env` | base-packages, zsh, git, starship, ssh, fonts, tailscale, claude-code, jira-cli, docker, custom-scripts |
| `setup` | user-setup + all `env` roles |
| `desktop` | i3, rofi, dunst, kitty, touchpad |
| `media` | docker-stacks |
| `thinkpad-x1` | fingerprint, tlp, accelerometer, wwan |

Combine: `--tags env,desktop`

New roles must be added to `site.yml` with appropriate tags.

## Writing Roles

### Multi-distro dispatch

Use `ansible_os_family` for distro-specific tasks:

```yaml
# tasks/main.yml
- name: Include distro-specific tasks
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

Supported families: `archlinux`, `debian`. Skip non-applicable roles with:

```yaml
- name: Skip on non-Linux
  ansible.builtin.meta: end_play
  when: ansible_system != 'Linux'
```

### Packages

- Arch: `community.general.pacman`
- Debian: `ansible.builtin.apt` (with `update_cache: true`)
- Cross-platform: `ansible.builtin.package`

### Config files

- User configs (dotfiles): `templates/` with `.j2` extension, dest to `/home/{{ target_user }}/` (env/setup roles) or `/home/{{ username }}/` (desktop roles)
- System configs that must be exact: `files/` with `ansible.builtin.copy`
- Never use `lineinfile` on PAM files — deploy the complete file

### Variables

- Shared vars: `group_vars/all/vars.yml`
- Secrets: `group_vars/all/vault.yml` (`vault_` prefix), reference in `vars.yml`
- Machine-specific: `host_vars/localhost.yml`
- Role defaults: `roles/<name>/defaults/main.yml`

### File permissions

| Type | Owner | Mode |
|------|-------|------|
| User configs (env roles) | `{{ target_user }}` | `0644` |
| User configs (desktop roles) | `{{ username }}` | `0644` |
| Secrets (keys, tokens) | `{{ target_user }}` | `0600` |
| Scripts | `{{ target_user }}` | `0755` |
| System configs | root | `0644` |

## Gotchas

- `become: true` makes `ansible_env.HOME` resolve to `/root` — use `/home/{{ target_user }}/` (env/setup roles) or `/home/{{ username }}/` (desktop roles)
- `host_vars` filename must match inventory hostname — `localhost.yml`, not the machine name
- `ansible_distribution` returns `Archlinux` not `EndeavourOS` on EndeavourOS
- `become_method` is `su`, not `sudo` — avoids fprintd PAM timeout during playbook runs
- PAM file ordering: `pam_fprintd.so` must go BEFORE `pam_unix.so` but AFTER `pam_faillock.so preauth`; update `success=N` skip counts if adding/removing lines
- Never use sed/lineinfile on `/etc/pam.d/` files — a bad edit locks you out of sudo
- `ansible-vault rekey` needs the old password to decrypt first, then re-encrypts with new
