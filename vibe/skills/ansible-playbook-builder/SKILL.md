---
name: ansible-playbook-builder
description: Infrastructure automation with Ansible, playbooks, roles, inventories, vault and modules. Triggers on "Ansible", "playbook", "ansible-playbook", "Ansible role", "Ansible vault", "server automation".
user-invocable: true
---

# Ansible Playbook Builder

## Workflow

### 1. Analyse the target infrastructure

List: operating systems (RHEL, Ubuntu, Debian), SSH access (key or bastion), connection user (`ansible_user`), sudo privileges.

**Decision criteria, static versus dynamic inventory:**
- Fewer than 20 stable hosts means a static INI or YAML inventory
- Cloud (AWS, Azure, GCP) or ephemeral infrastructure means a dynamic plugin (`amazon.aws.ec2`, `azure.azcollection.azure_rm`)

### 2. Structure the inventory

```ini
# inventories/production/hosts.ini
[web]
web01.prod.example.com ansible_user=deploy
web02.prod.example.com ansible_user=deploy

[db]
db01.prod.example.com ansible_user=deploy

[all:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

```
inventories/
  production/
    hosts.ini
    group_vars/
      all.yml          # variables communes
      web.yml          # variables groupe web
    host_vars/
      db01.prod.example.com.yml
  staging/
    hosts.ini
    group_vars/
```

Test connectivity before any playbook:
```bash
ansible all -i inventories/production/hosts.ini -m ping
```

### 3. Design the playbooks

Minimal production-ready structure:

```yaml
# site.yml
---
- name: Configure web servers
  hosts: web
  become: true
  gather_facts: true
  tags: [web]

  pre_tasks:
    - name: Ensure Python3 is present
      ansible.builtin.raw: apt-get install -y python3
      changed_when: false

  roles:
    - role: common
    - role: nginx
      vars:
        nginx_port: 443

  post_tasks:
    - name: Verify nginx is responding
      ansible.builtin.uri:
        url: "https://{{ ansible_fqdn }}"
        status_code: 200
      delegate_to: localhost
```

**Common commands:**
```bash
# Dry-run avec diff
ansible-playbook -i inventories/production/hosts.ini site.yml --check --diff

# Targeted run by tag
ansible-playbook site.yml -i inventories/production/hosts.ini --tags nginx

# Limit to one host
ansible-playbook site.yml -i inventories/production/hosts.ini --limit web01.prod.example.com

# Verbose for debugging
ansible-playbook site.yml -vvv
```

### 4. Build the roles

Standard structure to follow:
```
roles/nginx/
  tasks/
    main.yml
    install.yml
    configure.yml
  handlers/
    main.yml          # notify: Restart nginx
  templates/
    nginx.conf.j2
  files/
    dhparam.pem
  defaults/
    main.yml          # overridable variables (low precedence)
  vars/
    main.yml          # internal variables (high precedence)
  meta/
    main.yml          # dependencies, galaxy_info
```

`defaults/main.yml`, always document it:
```yaml
# HTTP listening port
nginx_http_port: 80
# HTTPS listening port (0 disables it)
nginx_https_port: 443
# Nombre de workers (auto = nb CPUs)
nginx_worker_processes: auto
```

Handler example:
```yaml
# handlers/main.yml
- name: Restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted
  listen: Restart nginx
```

### 5. Secure with Ansible Vault

```bash
# Encrypt a secrets file
ansible-vault encrypt inventories/production/group_vars/all/vault.yml

# Edit an encrypted file
ansible-vault edit inventories/production/group_vars/all/vault.yml

# Run with the vault password
ansible-playbook site.yml --vault-password-file ~/.vault_pass.txt
# ou via variable d'environnement CI/CD
ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass.txt ansible-playbook site.yml
```

Naming convention, prefix encrypted variables with `vault_`:
```yaml
# group_vars/all/vars.yml (clair)
db_password: "{{ vault_db_password }}"

# group_vars/all/vault.yml (encrypted)
vault_db_password: "S3cr3t!"
```

### 6. Jinja2 templates

```jinja2
{# templates/nginx.conf.j2 #}
worker_processes {{ nginx_worker_processes }};

server {
    listen {{ nginx_https_port }} ssl;
    server_name {{ ansible_fqdn }};

    {% for location in nginx_locations %}
    location {{ location.path }} {
        proxy_pass {{ location.backend }};
    }
    {% endfor %}
}
```

Useful filters:
```yaml
# Convertir en majuscules
- debug: msg="{{ env | upper }}"
# Default value
- debug: msg="{{ timeout | default(30) }}"
# Join a list
- debug: msg="{{ groups['web'] | join(',') }}"
```

### 7. Test the playbooks

```bash
# Lint (ansible-lint >= 6)
pip install ansible-lint
ansible-lint site.yml

# Syntaxe seule
ansible-playbook --syntax-check site.yml

# Test de role avec Molecule (driver Docker)
pip install molecule molecule-docker
cd roles/nginx
molecule init scenario --driver-name docker
molecule test   # create → converge → verify → destroy
```

Minimal `molecule/default/verify.yml`:
```yaml
- name: Verify nginx
  hosts: all
  tasks:
    - name: Check nginx service is running
      service_facts:
    - assert:
        that: "'nginx' in services and services['nginx'].state == 'running'"
```

### 8. Orchestrate the deployments

**Rolling update:**
```yaml
- hosts: web
  serial: "25%"        # 25% of the hosts at a time
  max_fail_percentage: 0
  roles:
    - nginx
```

**CI/CD integration (GitHub Actions):**
```yaml
- name: Deploy to production
  run: |
    ansible-playbook -i inventories/production/hosts.ini site.yml \
      --vault-password-file <(echo "$VAULT_PASS") \
      --diff
  env:
    VAULT_PASS: ${{ secrets.ANSIBLE_VAULT_PASS }}
```

## Guardrails, anti-patterns and pitfalls

| Anti-pattern | Risk | Fix |
|---|---|---|
| `shell: rm -rf /tmp/{{ app }}` | Idempotence broken plus injection risk | `file: path=... state=absent` |
| `command: service nginx restart` | Not idempotent | The `service` module plus a handler |
| Plaintext variables in git | Secret leak | Ansible Vault is mandatory |
| `ignore_errors: true` everywhere | Silent failures in production | Handle the failure cases explicitly |
| `gather_facts: false` by default | Loss of the `ansible_*` variables | Disable it only when performance is critical, and document it |
| No `--check` before production | Unexpected changes | Always dry-run on staging first |
| `become: true` on the whole playbook | Wider attack surface | `become: true` only on the tasks that need it |

## Good practice for 2026

- **Collections over community roles**: use `ansible.posix`, `community.general`, `community.docker` through `requirements.yml` plus `ansible-galaxy collection install -r requirements.yml`.
- **Version `ansible.cfg`** in the repository: `[defaults] host_key_checking = True`, `forks = 10`, `callback_whitelist = profile_tasks`.
- **Pin the Ansible version** in CI (`pip install ansible-core==2.21.*`) to avoid regressions.
- **No `with_items` loop**, replace it with `loop`, the modern syntax since Ansible 2.5.
- **Fully qualified module names (FQCN)**: write `ansible.builtin.service`, not `service`.
  `ansible-lint`, which this workflow enforces, fails on short names (the `fqcn` rule).
- **Explicit `changed_when` and `failed_when`** on the unavoidable `command` and `shell` modules.
- **Secret rotation**: wire in HashiCorp Vault or AWS Secrets Manager through the `community.hashi_vault.vault_read` lookup rather than Ansible Vault alone for multi-team environments.
