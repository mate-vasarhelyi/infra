# Bootstrap Enhancement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enhance bootstrap.sh to work as a curl-able script for both new and existing systems, with optional playbook auto-run.

**Architecture:** Modify the existing bootstrap.sh — fix stdin for curl piping, add interactive run/tag prompts, update final message.

**Tech Stack:** Bash

---

### Task 1: Fix interactive reads for curl piping

**Files:**
- Modify: `bootstrap.sh:50-55` (vault password read)

**Context:** When the script is run via `curl | bash`, stdin is the pipe, so `read` can't get user input. Redirecting from `/dev/tty` fixes this.

**Step 1: Fix the vault password read**

Change lines 50-55 from:
```bash
if [ ! -f "$CLONE_DIR/.vault-pass" ]; then
    read -rsp "Ansible vault password: " vault_pass
    echo
    echo "$vault_pass" > "$CLONE_DIR/.vault-pass"
    chmod 600 "$CLONE_DIR/.vault-pass"
fi
```
to:
```bash
if [ ! -f "$CLONE_DIR/.vault-pass" ]; then
    read -rsp "Ansible vault password: " vault_pass </dev/tty
    echo
    echo "$vault_pass" > "$CLONE_DIR/.vault-pass"
    chmod 600 "$CLONE_DIR/.vault-pass"
fi
```

**Step 2: Verify syntax**

Run: `bash -n bootstrap.sh`
Expected: no output (clean parse)

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "fix(bootstrap): use /dev/tty for vault read to support curl piping"
```

---

### Task 2: Add playbook run prompt and tag menu

**Files:**
- Modify: `bootstrap.sh:57-60` (replace the final echo block)

**Context:** Replace the static "Ready!" message with an interactive prompt. If user chooses to run, present a tag menu (env, setup, or custom). Then run the playbook with `--ask-become-pass`.

**Step 1: Replace the final block**

Replace lines 57-60:
```bash
echo ""
echo "Ready! Run your playbook:"
echo "  cd $CLONE_DIR"
echo "  ansible-playbook site.yml --tags common"
```

with:
```bash
echo ""
echo "=== Bootstrap complete ==="
echo ""
read -rp "Run the playbook now? [y/N] " run_now </dev/tty
if [[ "$run_now" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Which tags?"
    echo "  1) env    — packages + config for current user"
    echo "  2) setup  — create user + full env (new systems)"
    echo "  3) custom — enter your own tags"
    echo ""
    read -rp "Choice [1/2/3]: " tag_choice </dev/tty
    case "$tag_choice" in
        1) tags="env" ;;
        2) tags="setup" ;;
        3)
            read -rp "Enter tags (comma-separated): " tags </dev/tty
            ;;
        *)
            echo "Invalid choice, exiting."
            exit 1
            ;;
    esac
    echo ""
    echo "Running: ansible-playbook site.yml --tags $tags --ask-become-pass"
    echo ""
    ansible-playbook site.yml --tags "$tags" --ask-become-pass
else
    echo ""
    echo "Ready! Run your playbook:"
    echo "  cd $CLONE_DIR"
    echo "  ansible-playbook site.yml --tags env --ask-become-pass    # existing system"
    echo "  ansible-playbook site.yml --tags setup --ask-become-pass  # new system"
fi
```

**Step 2: Verify syntax**

Run: `bash -n bootstrap.sh`
Expected: no output (clean parse)

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): add interactive playbook run with tag selection"
```

---

### Task 3: Verification

**Step 1: Full syntax check**

Run: `bash -n bootstrap.sh`
Expected: no output

**Step 2: Verify the script reads well**

Run: `cat bootstrap.sh`
Expected: clean script with all changes integrated

**Step 3: Shellcheck (if available)**

Run: `shellcheck bootstrap.sh || true`
Expected: no critical errors (SC2162 about read without -r is fine since we use -r)
