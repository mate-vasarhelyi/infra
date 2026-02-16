# Bootstrap Script Enhancement Design

## Goal

Make `bootstrap.sh` a one-stop curl-able script for both new and existing systems, with optional auto-run of the playbook.

## Decisions

- **Interactive prompts via `/dev/tty`:** All `read` calls use `</dev/tty` so the script works when piped from curl
- **Optional auto-run:** After prep, ask whether to run the playbook
- **Tag menu:** Present common options (env, setup) plus custom input
- **Pass `--ask-become-pass`:** Let Ansible handle the su password prompt natively
- **Keep existing logic:** Container sandbox workaround, brew support, vault setup all stay

## Flow

```
1. Install prereqs (git, ansible, system updates)
2. Clone or pull repo to ~/.infra
3. Install galaxy deps
4. Set up vault password
5. Ask "Run playbook now? [y/N]"
   → No: print available tags and example commands, exit
   → Yes: Ask which tags (env/setup/custom)
     → Run: ansible-playbook site.yml --tags <tags> --ask-become-pass
```

## Use Cases

**New system:** curl script → installs prereqs, clones repo → choose `setup` tag → creates user + full env
**Existing system:** curl script → prereqs already present, pulls latest → choose `env` tag → packages + config only

## Changes

1. **Modify `bootstrap.sh`** — add `/dev/tty` to reads, add run prompt, add tag menu, fix outdated `--tags common` message
