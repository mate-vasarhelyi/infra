# CI: GitHub Actions for Ansible Lint

**Date:** 2026-02-14
**Status:** Approved

## Problem

Changes to the Ansible repo can introduce syntax errors, deprecated module usage, or style issues that are only caught during manual playbook runs. A CI pipeline catches these automatically on every PR.

## Decision

Single GitHub Actions workflow running on PRs to `main`. Two checks:

1. **ansible-lint** — style, best practices, deprecated modules
2. **ansible-playbook --syntax-check** — YAML/Jinja syntax validation

No dry-run (`--check --diff`) — would require vault secrets in CI, creating a risk that malicious PRs could exfiltrate decrypted secrets via injected tasks.

## Design

### Workflow

`.github/workflows/ci.yml`:
- **Trigger:** `pull_request` targeting `main`
- **Runner:** `ubuntu-latest`
- **Steps:**
  1. Checkout repo
  2. Install Python 3 + pip
  3. Install ansible + ansible-lint via pip
  4. Install galaxy collections (`ansible-galaxy collection install -r requirements.yml`)
  5. Run `ansible-lint site.yml`
  6. Run `ansible-playbook site.yml --syntax-check`

### Lint configuration

`.ansible-lint` at repo root:
- Playbook: `site.yml`
- Exclude: `stacks/` (docker-compose files, not Ansible)
- Skip rules as needed based on initial lint output

### Security

- No vault password in CI (no GitHub Secrets needed)
- `--syntax-check` parses without evaluating vault variables
- `ansible-lint` is static analysis — no secrets needed
- Safe for untrusted PRs

### Trade-offs

**What it catches:** syntax errors, deprecated modules, style violations, YAML formatting, missing required fields, incorrect module usage.

**What it won't catch:** runtime errors (wrong package names, bad paths), distro-specific issues, vault variable mismatches. These are tested manually on LXC containers.
