# Docker CI Publish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically build and publish the dev environment Docker image to GHCR on every push to main, and provide a docker-compose.yml so users can run it with one command.

**Architecture:** A new GitHub Actions workflow uses `docker/build-push-action` with QEMU for multi-platform builds (amd64 + arm64). The image is pushed to `ghcr.io/mate-vasarhelyi/infra-dev` with `:latest` and `:sha-<short>` tags. A `docker-compose.yml` at the repo root references this image. The README is updated to lead with the pre-built image path.

**Tech Stack:** GitHub Actions, Docker Buildx, GHCR, Docker Compose

---

### Task 1: Create the GitHub Actions workflow

**Files:**
- Create: `.github/workflows/docker-publish.yml`

**Context:** The repo already has `.github/workflows/ci.yml` which runs ansible-lint on PRs. This new workflow is separate — it only triggers on pushes to main (not PRs) and handles Docker image building/publishing. The existing Dockerfile requires `--network=host` during build because Ansible's apt tasks need DNS resolution that BuildKit's default network doesn't provide.

**Step 1: Create the workflow file**

```yaml
---
name: Publish Docker image

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          network: host
          tags: |
            ghcr.io/${{ github.repository_owner }}/infra-dev:latest
            ghcr.io/${{ github.repository_owner }}/infra-dev:sha-${{ github.sha }}
```

Note: We use `github.repository_owner` (lowercase) which resolves to `mate-vasarhelyi`. The `network: host` parameter in `docker/build-push-action` maps to `--network=host` in the Docker build command, which is required because the Ansible playbook runs `apt-get` during build and BuildKit's default DNS resolution fails without it.

**Step 2: Validate the YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-publish.yml'))"`
Expected: No output (valid YAML)

**Step 3: Commit**

```bash
git add .github/workflows/docker-publish.yml
git commit -m "ci: add workflow to publish Docker image to GHCR"
```

---

### Task 2: Create docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

**Context:** This file goes at the repo root. Users will either clone the repo and `docker compose up`, or download just this file directly with `curl`. The image name must match what the CI workflow pushes: `ghcr.io/mate-vasarhelyi/infra-dev:latest`. Ports 8080 (code-server) and 7681 (ttyd+zellij) must be exposed.

**Step 1: Create the compose file**

```yaml
services:
  dev:
    image: ghcr.io/mate-vasarhelyi/infra-dev:latest
    ports:
      - "8080:8080"
      - "7681:7681"
    restart: unless-stopped
```

Note: No `version:` key — it's been deprecated since Docker Compose v2 and is ignored. Keep it minimal; users can add volumes or environment variables themselves.

**Step 2: Validate the compose file**

Run: `docker compose -f docker-compose.yml config`
Expected: Prints the resolved config with the image, ports, and restart policy. No errors.

If `docker compose` is not installed, use: `python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))"`

**Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add docker-compose.yml for pre-built image"
```

---

### Task 3: Update README.md

**Files:**
- Modify: `README.md`

**Context:** The current README leads with a "Quick Start (Docker)" section that tells users to clone the repo and build the image themselves. Replace this with a much simpler path using the pre-built GHCR image. Move the build-from-source instructions to a secondary section. Keep the troubleshooting section but update it for the new workflow.

**Step 1: Replace the Quick Start (Docker) section**

Replace everything from `## Quick Start (Docker)` up to (but not including) `## Quick Start (bare metal)` with:

```markdown
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
- **Want to persist your work:** Add a volume to `docker-compose.yml`:
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
docker compose up -d
```

Note: `--network=host` is required for the build because Ansible runs `apt-get` inside the build and BuildKit's default DNS can fail.
```

**Step 2: Update the Layout section**

Add `docker-compose.yml` to the layout tree. Find the line with `docker-entrypoint.sh` and add `docker-compose.yml` after it:

```
docker-compose.yml       # run pre-built image with docker compose
```

Also add the CI workflow. Find the line with `group_vars/all/vars.yml` (or wherever `group_vars` starts) and add before it:

```
.github/workflows/       # CI: lint (PRs) + Docker publish (main)
```

**Step 3: Verify no broken markdown**

Run: `python3 -c "open('README.md').read()"` (just verify it's readable, no syntax check needed for markdown)

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README with pre-built Docker image instructions"
```

---

### Task 4: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Context:** The CLAUDE.md is project instructions for Claude Code. It has a Layout section and a Docker section that need updating to reflect the new CI workflow and docker-compose.yml.

**Step 1: Update the Layout tree**

Add these entries to the layout tree in CLAUDE.md:

After the `.dockerignore` line, add:
```
├── docker-compose.yml    # Run pre-built image (docker compose up)
```

After the `requirements.yml` line, add:
```
├── .github/workflows/    # CI: lint (PRs) + Docker publish (main)
```

**Step 2: Update the Docker section**

Add to the Docker section in CLAUDE.md, after the existing bullet points:

```
- CI workflow (`.github/workflows/docker-publish.yml`) builds multi-platform image (amd64 + arm64) on every push to main and publishes to `ghcr.io/mate-vasarhelyi/infra-dev`
- `docker-compose.yml` at repo root references the GHCR image for easy `docker compose up`
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with CI workflow and compose file"
```
