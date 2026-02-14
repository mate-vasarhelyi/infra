# Cross-Distro Bootstrap Redesign

## Problem

The playbook was originally built for an existing Arch laptop. Fresh-machine bootstrap and Debian support were goals but never properly implemented. This caused cascading failures when spinning up Arch LXC containers and would completely break on Debian.

### Issues found

**Hard failures on Debian:**
1. `python-passlib` package name (Debian: `python3-passlib`)
2. `wheel` group doesn't exist (Debian: `sudo`)
3. sudoers `%wheel` regex has nothing to match in Debian's sudoers
4. `openssh` package doesn't exist (Debian: `openssh-client`)
5. `gh` CLI not in default Debian repos

**Structural issues:**
6. User creation, sudo, passlib all crammed into `site.yml` pre_tasks
7. `become_method = su` fails on Debian systems without a root password
8. `kubectl` Debian APT repo pinned to a specific version
9. `sudo-askpass` deployed on headless systems where `rofi` isn't installed

## Design

### 1. New `user-setup` role

Replace the growing pre_tasks block with a proper role using distro dispatch.

**`roles/user-setup/tasks/main.yml`:**
- Install sudo and passlib (distro-appropriate package names)
- Create user with vaulted password, correct admin group, `update_password: on_create`
- Configure sudoers for the correct group

**`roles/user-setup/tasks/archlinux.yml`:**
- Package: `python-passlib`
- Group: `wheel`
- Sudoers: uncomment `%wheel` line

**`roles/user-setup/tasks/debian.yml`:**
- Package: `python3-passlib`
- Group: `sudo`
- Sudoers: `%sudo` line (already enabled by default on Debian, verify it exists)

The role runs first in `site.yml` before all other roles. Pre_tasks goes back to just fact gathering.

### 2. Fix `openssh` package

Move `openssh` out of the shared `base_packages` list into distro-specific lists:
- Arch: `openssh`
- Debian: `openssh-client`

### 3. Fix `gh` CLI on Debian

Add the GitHub CLI APT repository in `base-packages/tasks/debian.yml` before installing `gh`.

### 4. Fix `kubectl` on Debian

Use a version-agnostic approach or latest stable version detection for the kubernetes APT repo.

### 5. Make `sudo-askpass` conditional

Only deploy the `sudo-askpass` script when rofi is available or when desktop tag is applied. The script is harmless when rofi isn't installed (it just fails silently), but cleaner to skip it.

Alternative: make `sudo-askpass` check for rofi and fall back to a terminal prompt. This is simpler and means the script always works.

### 6. Clean up `site.yml`

- Pre_tasks: only fact gathering
- `user-setup` role: first in the common tag
- Remove `python-passlib` and `sudo` from pre_tasks entirely

### Out of scope (for now)

- Desktop role Debian fixes (i3, fingerprint PAM, touchpad xorg)
- `become_method` change (su works in current bootstrap flow)
- Docker APT repo Ubuntu compatibility
