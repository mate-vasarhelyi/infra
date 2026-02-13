# infra

```bash
curl -fsSL https://raw.githubusercontent.com/mate-vasarhelyi/infra/main/bootstrap.sh | bash
```

Ansible playbook that configures my machines from a fresh install. Runs locally against localhost. Supports Arch and Debian.

## Usage

```bash
cd ~/.infra
ansible-playbook site.yml --tags common,desktop --ask-become-pass
```

## Tags

| Tag | What it sets up |
|-----|-----------------|
| `common` | base packages, zsh, git, starship, ssh, fonts, tailscale, claude code, docker |
| `desktop` | i3, rofi, dunst, kitty, touchpad |
| `media` | docker compose stacks (sonarr, radarr, etc.) |
| `thinkpad-x1` | fingerprint reader, tlp, accelerometer, wwan |

Combine tags: `--tags common,desktop,thinkpad-x1`

## Secrets

Secrets are stored in `group_vars/all/vault.yml` (encrypted with ansible-vault). Edit with:

```bash
ansible-vault edit group_vars/all/vault.yml
```

## Layout

```
site.yml                 # main playbook
ansible.cfg              # become_method=su, vault config
bootstrap.sh             # one-liner fresh install script
group_vars/all/vars.yml  # shared variables
group_vars/all/vault.yml # encrypted secrets
roles/<name>/            # ansible roles
stacks/<name>/           # docker compose stacks
```
