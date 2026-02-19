# Docker Dev Environment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Dockerfile and supporting files so others can spin up the Ansible-configured dev environment in Docker.

**Architecture:** Debian bookworm base image, playbook baked at build time with `--tags setup,remote-dev`. A `docker-defaults.yml` provides placeholder values for vault-referenced variables. A `container_mode` variable skips systemd tasks. Entrypoint starts code-server and ttyd directly.

**Tech Stack:** Docker, Ansible, Debian bookworm

---

### Task 1: Add `container_mode` guard to docker role

**Files:**
- Modify: `roles/docker/tasks/main.yml:10-14`

**Step 1: Add guard to systemd task**

In `roles/docker/tasks/main.yml`, add a `when` condition to the "Enable and start docker" task:

```yaml
- name: Enable and start docker
  ansible.builtin.systemd:
    name: docker
    enabled: true
    state: started
  when: not (container_mode | default(false))
```

**Step 2: Commit**

```bash
git add roles/docker/tasks/main.yml
git commit -m "fix(docker): skip systemd start in container mode"
```

---

### Task 2: Add `container_mode` guard to remote-dev role

**Files:**
- Modify: `roles/remote-dev/tasks/main.yml:18-30`
- Modify: `roles/remote-dev/handlers/main.yml:1-13`

**Step 1: Update systemd tasks in tasks/main.yml**

Replace the existing `when: not ansible_check_mode` guards on both systemd tasks with a combined guard:

```yaml
- name: Enable and start code-server
  ansible.builtin.systemd:
    name: code-server
    enabled: true
    state: started
  when: not ansible_check_mode and not (container_mode | default(false))

- name: Enable and start ttyd
  ansible.builtin.systemd:
    name: ttyd
    enabled: true
    state: started
  when: not ansible_check_mode and not (container_mode | default(false))
```

**Step 2: Update handlers**

Add the same guard to both handlers in `roles/remote-dev/handlers/main.yml`:

```yaml
- name: Restart code-server
  ansible.builtin.systemd:
    name: code-server
    state: restarted
    daemon_reload: true
  when: not ansible_check_mode and not (container_mode | default(false))

- name: Restart ttyd
  ansible.builtin.systemd:
    name: ttyd
    state: restarted
    daemon_reload: true
  when: not ansible_check_mode and not (container_mode | default(false))
```

**Step 3: Commit**

```bash
git add roles/remote-dev/tasks/main.yml roles/remote-dev/handlers/main.yml
git commit -m "fix(remote-dev): skip systemd tasks in container mode"
```

---

### Task 3: Add vault-skip guards to claude-code and jira-cli roles

**Files:**
- Modify: `roles/claude-code/tasks/main.yml:33-42`
- Modify: `roles/jira-cli/tasks/main.yml:28`

**Step 1: Guard claude-code credentials task**

Add `when: claude_oauth_refresh_token is defined` to the "Deploy OAuth credentials" task at line 33:

```yaml
- name: Deploy OAuth credentials (only if not present)
  ansible.builtin.template:
    src: credentials.json.j2
    dest: "/home/{{ target_user }}/.claude/.credentials.json"
    owner: "{{ target_user }}"
    mode: "0600"
    force: false
  become: true
  become_user: "{{ target_user }}"
  no_log: true
  when: claude_oauth_refresh_token is defined
```

**Step 2: Strengthen jira-cli guard**

Change line 28 of `roles/jira-cli/tasks/main.yml` from `when: jira_server is defined` to:

```yaml
  when: jira_server is defined and jira_login is defined
```

**Step 3: Commit**

```bash
git add roles/claude-code/tasks/main.yml roles/jira-cli/tasks/main.yml
git commit -m "fix: guard vault-dependent tasks for secretless runs"
```

---

### Task 4: Create `docker-defaults.yml`

**Files:**
- Create: `docker-defaults.yml`

**Step 1: Create the defaults file**

```yaml
# Placeholder values for running the playbook without vault secrets.
# Tools are installed but not pre-authenticated — users log in manually.
user_password: "changeme"
git_email: "dev@localhost"
github_token: "replace_me"
container_mode: true
```

**Step 2: Commit**

```bash
git add docker-defaults.yml
git commit -m "feat: add docker-defaults.yml for secretless playbook runs"
```

---

### Task 5: Create `docker-entrypoint.sh`

**Files:**
- Create: `docker-entrypoint.sh`

**Step 1: Create the entrypoint script**

```bash
#!/bin/bash
code-server --bind-addr 0.0.0.0:8080 --auth none &
exec ttyd -p 7681 -W zellij
```

Uses `exec` so ttyd replaces the shell and receives signals properly.

**Step 2: Make it executable**

```bash
chmod +x docker-entrypoint.sh
```

**Step 3: Commit**

```bash
git add docker-entrypoint.sh
git commit -m "feat: add Docker entrypoint for code-server and ttyd"
```

---

### Task 6: Create `.dockerignore`

**Files:**
- Create: `.dockerignore`

**Step 1: Create the ignore file**

```
.git
.vault-pass
*.retry
docs/
```

**Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add .dockerignore"
```

---

### Task 7: Create `Dockerfile`

**Files:**
- Create: `Dockerfile`

**Step 1: Write the Dockerfile**

```dockerfile
FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git ansible python3-passlib sudo curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY . /tmp/infra
WORKDIR /tmp/infra

RUN ansible-galaxy collection install -r requirements.yml

RUN ansible-playbook site.yml \
    --tags setup,remote-dev \
    --extra-vars "@docker-defaults.yml" \
    --extra-vars "target_user=dev" \
    --connection=local

RUN apt-get purge -y ansible \
    && apt-get autoremove -y \
    && rm -rf /tmp/infra /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/
USER dev
WORKDIR /home/dev
EXPOSE 8080 7681

ENTRYPOINT ["docker-entrypoint.sh"]
```

**Step 2: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile for containerized dev environment"
```

---

### Task 8: Build and test the Docker image

**Step 1: Build the image**

```bash
cd ~/.infra
docker build -t infra-dev .
```

Expected: Build completes successfully. Watch for errors in the Ansible playbook run.

**Step 2: Run the container**

```bash
docker run -d --name infra-test -p 8080:8080 -p 7681:7681 infra-dev
```

**Step 3: Verify services are reachable**

```bash
# Wait a few seconds for startup
sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080
# Expected: 200

curl -s -o /dev/null -w "%{http_code}" http://localhost:7681
# Expected: 200
```

**Step 4: Verify dev user and tools**

```bash
docker exec infra-test whoami
# Expected: dev

docker exec infra-test zsh -c 'which code-server ttyd zellij git gh jira node claude'
# Expected: paths for each binary

docker exec infra-test zsh -c 'starship --version'
# Expected: version output
```

**Step 5: Clean up**

```bash
docker stop infra-test && docker rm infra-test
```

**Step 6: Final commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: address issues found during Docker build testing"
```
