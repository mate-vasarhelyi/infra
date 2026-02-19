# Docker CI Publish Design

## Goal

Automatically build and publish the dev environment Docker image to GHCR on every push to main, so users can run it with a single `docker compose up` instead of cloning and building locally.

## Architecture

A new GitHub Actions workflow (`docker-publish.yml`) builds a multi-platform image (amd64 + arm64) on every push to main and pushes it to `ghcr.io/mate-vasarhelyi/infra-dev`. A `docker-compose.yml` at the repo root references this image for easy consumption. The README is updated to lead with the pre-built image path.

## Registry

- **GHCR** (`ghcr.io/mate-vasarhelyi/infra-dev`)
- Authentication via `GITHUB_TOKEN` (automatic in GitHub Actions, no manual secret setup)
- Public image (matches public repo)

## CI Workflow

**File:** `.github/workflows/docker-publish.yml`

**Trigger:** Push to `main` branch only

**Steps:**
1. Checkout repo
2. Set up QEMU (ARM64 cross-compilation)
3. Set up Docker Buildx
4. Login to GHCR with `GITHUB_TOKEN`
5. Build multi-platform (`linux/amd64`, `linux/arm64`) with `--network=host`
6. Push with tags: `latest` + short git SHA

**Permissions:** `packages: write`, `contents: read`

The existing `ci.yml` (ansible-lint on PRs) remains untouched.

## Docker Compose File

**File:** `docker-compose.yml` (repo root)

```yaml
services:
  dev:
    image: ghcr.io/mate-vasarhelyi/infra-dev:latest
    ports:
      - "8080:8080"
      - "7681:7681"
    restart: unless-stopped
```

## README Changes

- Lead Quick Start with pre-built image: `curl` compose file + `docker compose up -d`
- Move clone-and-build to "Build from source" subsection
- Keep troubleshooting, add image pull notes

## Files Changed

| File | Action |
|------|--------|
| `.github/workflows/docker-publish.yml` | Create |
| `docker-compose.yml` | Create |
| `README.md` | Update |
| `CLAUDE.md` | Update layout |
