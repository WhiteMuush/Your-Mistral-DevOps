---
name: argocd-guide
description: GitOps with ArgoCD covering applications, sync, rollbacks, multi-cluster and the App of Apps pattern. Triggers on "ArgoCD", "Argo CD", "GitOps", "ArgoCD sync", "ArgoCD application", "App of Apps"
user-invocable: true
---

# ArgoCD Guide

## 1. Installation and initial configuration

```bash
# Helm (recommended in production)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.insecure=false \
  --set configs.params."server\.insecure"=false \
  -f argocd-values.yaml

# Retrieve the initial admin password
argocd admin initial-password -n argocd

# Login CLI
argocd login argocd.example.com --username admin --grpc-web
```

**SSO (Azure AD OIDC), minimal configuration in `argocd-cm`:**
```yaml
data:
  oidc.config: |
    name: Azure
    issuer: https://login.microsoftonline.com/<tenant-id>/v2.0
    clientID: <app-id>
    clientSecret: $oidc.azure.clientSecret
    requestedScopes: [openid, profile, email]
```

**RBAC, `argocd-rbac-cm`:**
```yaml
data:
  policy.csv: |
    p, role:developer, applications, sync, */*, allow
    p, role:developer, applications, get, */*, allow
    g, team-dev@example.com, role:developer
  policy.default: role:readonly
```

---

## 2. Connect a Git repository

```bash
# SSH key
argocd repo add git@github.com:org/gitops-repo.git \
  --ssh-private-key-path ~/.ssh/id_ed25519

# HTTPS token
argocd repo add https://github.com/org/gitops-repo.git \
  --username argocd --password <token>
```

**Recommended repository structure (monorepo):**
```
gitops-repo/
├── apps/                   # App of Apps (root)
│   ├── dev/
│   └── prod/
├── manifests/
│   ├── my-app/
│   │   ├── base/
│   │   └── overlays/
│   │       ├── dev/
│   │       └── prod/
└── infra/
    └── monitoring/
```

---

## 3. Declare an Application (declarative YAML)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # cascade delete
spec:
  project: production
  source:
    repoURL: git@github.com:org/gitops-repo.git
    targetRevision: main
    path: manifests/my-app/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: false          # JAMAIS true en prod sans sync window
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - RespectIgnoreDifferences=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**Sync policy criteria:**
| Environment | auto-sync | prune | selfHeal | Sync window |
|-----|-----------|-------|----------|-------------|
| dev | yes | yes | yes | no |
| staging | yes | yes | yes | optional |
| production | no (or yes) | **no** | yes | **mandatory** |

---

## 4. App of Apps, bootstrapping a cluster

```yaml
# root-app.yaml, applied manually once
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:org/gitops-repo.git
    targetRevision: HEAD
    path: apps/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

The `apps/prod/` directory holds one `Application` YAML per workload. ArgoCD creates them in cascade. A single `kubectl apply -f root-app.yaml` bootstraps the entire cluster.

---

## 5. ApplicationSet, multi-cluster and multi-environment

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-clusters
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: production
  template:
    metadata:
      name: "my-app-{{name}}"
    spec:
      project: production
      source:
        repoURL: git@github.com:org/gitops-repo.git
        targetRevision: main
        path: "manifests/my-app/overlays/{{metadata.labels.env}}"
      destination:
        server: "{{server}}"
        namespace: my-app
```

**Register a remote cluster:**
```bash
# Le context kubeconfig doit pointer sur le cluster cible
argocd cluster add prod-eu-west \
  --name prod-eu-west \
  --label env=production
```

---

## 6. Sync waves and hooks

Control the deployment order, for instance a CRD before its operator, or a database migration before the application:

```yaml
# CRD deployed in wave -1, before everything else
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
---
# Job de migration en wave 0
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
---
# App en wave 1
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

---

## 7. Rollback

```bash
# Lister l'historique
argocd app history my-app-prod

# Roll back to an earlier revision (ID taken from history)
argocd app rollback my-app-prod <revision-id>

# Force a sync onto a specific Git commit
argocd app set my-app-prod --revision abc1234
argocd app sync my-app-prod
```

After a manual rollback, disable auto-sync, otherwise ArgoCD immediately syncs back to HEAD:
```bash
argocd app set my-app-prod --sync-policy none
```

---

## 8. Secrets, never stored in plaintext in Git

| Tool | When to use it |
|-------|-----------------|
| **External Secrets Operator** | Secrets living in Vault, AWS SSM or Azure Key Vault, the 2026 recommendation |
| **SOPS with age or KMS** | In-repo encryption, manual rotation, simple to audit |
| **Sealed Secrets** | Cluster-specific, with no external dependency |

```yaml
# ExternalSecret (ESO)
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-creds
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-creds
  data:
    - secretKey: password
      remoteRef:
        key: secret/my-app/db
        property: password
```

---

## 9. Monitoring and notifications

```bash
# Prometheus metrics exposed by argocd-metrics:8082
# Alertes utiles :
# argocd_app_sync_total{phase="Error"} > 0
# argocd_app_health_status{health_status!="Healthy"} > 0
```

**Slack notification (argocd-notifications):**
```yaml
# argocd-notifications-cm
data:
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
  template.app-sync-failed: |
    message: |
      App {{.app.metadata.name}} sync FAILED: {{.app.status.operationState.message}}
```

---

## Anti-patterns and pitfalls

- **`prune: true` in production without a sync window**, it deletes unexpected resources as soon as they disappear from the repository, so one forgotten file becomes an outage.
- **Creating Applications only through the UI or the CLI**, which is not auditable and vanishes if ArgoCD is recreated. Always commit the YAML.
- **Storing plaintext secrets in the GitOps repository**, an immediate breach if the repository is compromised. Use ESO or SOPS.
- **Ignoring sync waves for CRDs**, ArgoCD tries to create custom resources before the CRD exists, which fails the sync.
- **A single `default` AppProject for every environment**, which loses RBAC isolation. Create one AppProject per team or environment.
- **`targetRevision: HEAD` in production**, an accidental merge deploys at once. Prefer a tag or a fixed sha, or use a sync window.
- **Missing health checks for CRDs**, ArgoCD reports `Healthy` even when the operator is failing. Define a custom Lua health check.

```lua
-- Exemple health check Lua pour un CRD custom
hs = {}
if obj.status ~= nil then
  if obj.status.phase == "Ready" then
    hs.status = "Healthy"
  elseif obj.status.phase == "Failed" then
    hs.status = "Degraded"
    hs.message = obj.status.message
  else
    hs.status = "Progressing"
  end
else
  hs.status = "Progressing"
end
return hs
```

---

## Good practice for 2026

- Use **ArgoCD 3.x** (3.3 is the current stable). The 2.x to 3.0 step, released in May 2025, brings
  behavioural changes: read the official migration guide before upgrading an existing cluster.
- Enable **server-side apply** (`ServerSideApply=true` in syncOptions) to avoid field manager conflicts.
- Prefer **Kustomize** for environment overlays and **Helm** for third-party library charts.
- Wire in **Argo Rollouts** for progressive delivery (canary, blue-green) rather than the native Kubernetes rolling updates.
- Version the `AppProject` and `ApplicationSet` objects in Git like any other ArgoCD resource.
- Enable `impersonation` so each Application runs with a dedicated ServiceAccount, limiting the blast radius.
