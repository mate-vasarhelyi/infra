# GitHub Actions CI Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a GitHub Actions workflow that runs ansible-lint on every PR to main.

**Architecture:** Single workflow file + ansible-lint config at repo root. ansible-lint handles both style checking and syntax validation internally, so no separate `--syntax-check` step is needed. This avoids the vault decryption problem — ansible-lint doesn't need to decrypt `group_vars/all/vault.yml` to lint task structure, but `ansible-playbook --syntax-check` does need it to load variable files.

**Tech Stack:** GitHub Actions, ansible-lint, pip

---

### Task 1: Run ansible-lint locally and capture baseline

**Context:** Before configuring anything, we need to see what ansible-lint flags on the current codebase so we know which rules to skip vs fix.

**Files:**
- None modified (read-only task)

**Step 1: Install ansible-lint locally**

```bash
pip install ansible-lint --user
```

**Step 2: Run ansible-lint against site.yml with no config**

```bash
cd ~/.infra && ansible-lint site.yml 2>&1 | head -100
```

**Step 3: Capture the full output**

Record which rules fire and on which files. Categorize into:
- **Fix:** legitimate issues we should fix (e.g. missing `changed_when` on command tasks that should have it)
- **Skip:** rules that don't make sense for this repo (e.g. `no-changed-when` on install scripts that inherently change state)

**Step 4: Commit nothing** — this is analysis only.

---

### Task 2: Create `.ansible-lint` configuration

**Context:** Based on Task 1 output, configure ansible-lint to skip rules that are false positives for this repo while keeping useful checks enabled.

**Files:**
- Create: `.ansible-lint`

**Step 1: Create `.ansible-lint`**

Start with this baseline and adjust based on Task 1 findings:

```yaml
# Ansible-lint configuration
profile: moderate

# Exclude non-Ansible files
exclude_paths:
  - stacks/
  - docs/
  - .github/

# Skip rules that produce false positives for this repo
# (adjust list based on Task 1 analysis)
skip_list: []
```

Possible skip candidates (confirm from Task 1 output):
- `no-changed-when` — many shell/command tasks are install scripts
- `command-instead-of-shell` — some tasks legitimately need shell features (pipes, env vars)
- `yaml[truthy]` — if it flags `true`/`false` in ansible tasks

**Step 2: Run ansible-lint with the config**

```bash
ansible-lint site.yml
```

Expected: Clean or near-clean output. Iterate on skip_list until all remaining warnings are legitimate fixes.

**Step 3: Fix any legitimate issues the linter finds**

For each real issue, fix it in the role. Common fixes:
- Add `changed_when: false` to command/shell tasks that are read-only (like `tailscale status --json`)
- Switch `shell` to `command` where shell features aren't needed

**Step 4: Commit**

```bash
git add .ansible-lint
git add -u  # any role fixes
git commit -m "add ansible-lint config and fix lint warnings"
```

---

### Task 3: Create GitHub Actions workflow

**Context:** Now that ansible-lint runs clean locally, create the CI workflow.

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create the workflow file**

```yaml
name: Ansible Lint

on:
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'

      - name: Install dependencies
        run: |
          pip install ansible ansible-lint
          ansible-galaxy collection install -r requirements.yml

      - name: Run ansible-lint
        run: ansible-lint site.yml
```

Note: No `vault_password_file` needed — ansible-lint doesn't decrypt vault files. Override the ansible.cfg setting in CI by setting `ANSIBLE_VAULT_PASSWORD_FILE` env to empty:

```yaml
      - name: Run ansible-lint
        env:
          ANSIBLE_VAULT_PASSWORD_FILE: ""
        run: ansible-lint site.yml
```

**Step 2: Verify the workflow is valid YAML**

```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

**Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "add GitHub Actions CI workflow for ansible-lint"
```

---

### Task 4: Test the CI pipeline

**Context:** Push a branch, open a PR, and verify the workflow runs successfully.

**Step 1: Push the branch and create a PR**

```bash
git push -u origin feature/ci-pipeline
gh pr create --title "Add GitHub Actions CI for ansible-lint" --body "..."
```

**Step 2: Watch the CI run**

```bash
gh pr checks <pr-number> --watch
```

Expected: Green check on the `lint` job.

**Step 3: If CI fails, debug and fix**

- Read the CI log: `gh run view <run-id> --log`
- Common issues:
  - Vault password file not found → ensure `ANSIBLE_VAULT_PASSWORD_FILE: ""` env is set
  - Galaxy collection install fails → check `requirements.yml` is correct
  - Lint rules fire on CI that didn't locally → ensure `.ansible-lint` is committed

**Step 4: Merge or hand off to user**

Use superpowers:finishing-a-development-branch.
