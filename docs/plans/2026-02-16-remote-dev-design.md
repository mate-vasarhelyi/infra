# Remote Dev Role Design

## Goal

A single `remote-dev` role that installs code-server and ttyd+zellij as systemd services, so any VM can be turned into a remote dev environment with a browser-based VS Code and terminal.

## Decisions

- **Systemd services on host** (not Docker) — full native filesystem access
- **No auth** — accessed over tailnet + LAN only
- **Single role** — code-server and ttyd are a logical pair
- **Both Arch and Debian** — distro dispatch like other roles

## Role Structure

```
roles/remote-dev/
├── tasks/
│   ├── main.yml           # Distro dispatch + systemd unit deployment + enable/start
│   ├── debian.yml          # Install code-server + ttyd on Debian
│   └── archlinux.yml       # Install code-server + ttyd on Arch
├── defaults/main.yml       # Ports, ttyd version
├── templates/
│   ├── code-server.service.j2
│   └── ttyd.service.j2
└── handlers/main.yml       # Restart handlers
```

## Installation

| Tool | Debian | Arch |
|------|--------|------|
| code-server | Official install script (`creates: /usr/bin/code-server`) | `community.general.pacman` |
| ttyd | GitHub release binary to `/usr/local/bin/ttyd` | `community.general.pacman` |
| zellij | Already in `base-packages` | Already in `base-packages` |

## Systemd Units

Both services run as `{{ target_user }}`, restart on failure.

- **code-server**: `--bind-addr 0.0.0.0:8080 --auth none /`
- **ttyd**: `-p 7681 -W zellij`

## Defaults

```yaml
code_server_port: 8080
ttyd_port: 7681
ttyd_version: "1.7.7"
```

## site.yml

```yaml
- role: remote-dev
  tags: [remote-dev]
```

## Tag Table

| Tag | Roles |
|-----|-------|
| `remote-dev` | remote-dev |
