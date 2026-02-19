# infra

Ansible playbook that configures dev machines from a fresh install. Runs locally against localhost. Supports Arch and Debian.

## Quick Start (Docker)

No Ansible knowledge needed. Just Docker.

```bash
git clone https://github.com/mate-vasarhelyi/infra.git
cd infra
docker build --network=host -t infra-dev .
docker run -d -p 8080:8080 -p 7681:7681 --name dev infra-dev
```

Then open in your browser:

- **Code editor:** http://localhost:8080 (VS Code in the browser)
- **Terminal:** http://localhost:7681 (zellij terminal in the browser)

That's it. You have a full dev environment with zsh, starship, git, node, claude code, and more.

To stop and remove:

```bash
docker stop dev && docker rm dev
```

To rebuild after pulling new changes:

```bash
git pull
docker build --network=host -t infra-dev .
```

### What's included

The Docker image comes with: zsh + starship prompt, git + GitHub CLI, Node.js (via nvm), Claude Code, Jira CLI, zellij, ripgrep, fd, bat, htop, kubectl, and Docker CLI.

Tools that need authentication (Claude Code, GitHub CLI, Jira CLI) are installed but not logged in. Run them once in the terminal to go through their login flow.

### Troubleshooting

- **Build fails with DNS errors:** Make sure you use `--network=host` in the build command.
- **Port already in use:** Change the host port, e.g. `-p 9080:8080 -p 9681:7681`, then access on those ports instead.
- **Want to persist your work:** Mount a volume: `docker run -d -p 8080:8080 -p 7681:7681 -v ~/projects:/home/dev/projects --name dev infra-dev`

## Quick Start (bare metal)

```bash
curl -fsSL https://raw.githubusercontent.com/mate-vasarhelyi/infra/main/bootstrap.sh | bash
```

This clones the repo to `~/.infra`, installs Ansible, and runs the playbook interactively.

### Manual run

```bash
cd ~/.infra
ansible-playbook site.yml --tags <tags> --ask-become-pass -e target_user=<username>
```

## Tags

| Tag | What it sets up |
|-----|-----------------|
| `env` | base packages, zsh, git, starship, ssh, fonts, claude code, jira-cli, nvm, docker, custom-scripts |
| `setup` | user creation + everything in `env` |
| `desktop` | i3, rofi, dunst, kitty, touchpad |
| `media` | docker compose stacks (jellyfin, sonarr) |
| `remote-dev` | code-server, ttyd + zellij |
| `tailscale` | tailscale VPN |
| `thinkpad-x1` | fingerprint reader, tlp, accelerometer, wwan |

Combine tags: `--tags env,desktop,thinkpad-x1`

## Secrets

Secrets are stored in `group_vars/all/vault.yml` (encrypted with ansible-vault). Edit with:

```bash
ansible-vault edit group_vars/all/vault.yml
```

## Layout

```
site.yml                 # main playbook
ansible.cfg              # become_method=sudo, vault config
bootstrap.sh             # one-liner fresh install script
Dockerfile               # containerized dev environment
docker-defaults.yml      # placeholder values for Docker (no secrets needed)
docker-entrypoint.sh     # starts code-server + ttyd in container
group_vars/all/vars.yml  # shared variables
group_vars/all/vault.yml # encrypted secrets
roles/<name>/            # ansible roles
stacks/<name>/           # docker compose stacks
```
