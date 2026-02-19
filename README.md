# infra

Ansible playbook that configures dev machines from a fresh install. Runs locally against localhost. Supports Arch and Debian.

## Quick Start (Docker)

No Ansible knowledge needed. Just Docker.

```bash
curl -fsSL https://raw.githubusercontent.com/mate-vasarhelyi/infra/main/docker-compose.yml -o docker-compose.yml
docker compose up -d
```

Then open in your browser:

- **Code editor:** http://localhost:8080 (VS Code in the browser)
- **Terminal:** http://localhost:7681 (zellij terminal in the browser)

That's it. You have a full dev environment with zsh, starship, git, node, claude code, and more.

To stop and remove:

```bash
docker compose down
```

To pull the latest image:

```bash
docker compose pull && docker compose up -d
```

### What's included

The Docker image comes with: zsh + starship prompt, git + GitHub CLI, Node.js (via nvm), Claude Code, Jira CLI, zellij, ripgrep, fd, bat, htop, kubectl, and Docker CLI.

Tools that need authentication (Claude Code, GitHub CLI, Jira CLI) are installed but not logged in. Run them once in the terminal to go through their login flow.

### Troubleshooting

- **Port already in use:** Change the host port in `docker-compose.yml`, e.g. `"9080:8080"`, then access on that port instead.
- **Want to persist your work:** Add a volume to `docker-compose.yml` under the `dev` service:
  ```yaml
      volumes:
        - ~/projects:/home/dev/projects
  ```

### Build from source

If you prefer to build the image yourself instead of using the pre-built one:

```bash
git clone https://github.com/mate-vasarhelyi/infra.git
cd infra
docker build --network=host -t infra-dev .
docker run -d -p 8080:8080 -p 7681:7681 --name dev infra-dev
```

Note: `--network=host` is required for the build because Ansible runs `apt-get` inside the build and BuildKit's default DNS can fail.

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
docker-compose.yml       # run pre-built image with docker compose
docker-defaults.yml      # placeholder values for Docker (no secrets needed)
docker-entrypoint.sh     # starts code-server + ttyd in container
.github/workflows/       # CI: lint (PRs) + Docker publish (main)
group_vars/all/vars.yml  # shared variables
group_vars/all/vault.yml # encrypted secrets
roles/<name>/            # ansible roles
stacks/<name>/           # docker compose stacks
```
