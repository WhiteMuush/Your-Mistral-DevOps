---
name: helm-chart-builder
description: Designing Helm charts for Kubernetes, templates, values, dependencies and deployment strategies. Use it when the user creates or modifies Helm charts, configures Kubernetes deployments or manages releases. Also triggers on "helm", "helm chart", "helm template", "values.yaml", "helm install", "helm upgrade", "kubernetes helm".
user-invocable: true
---

# Helm chart builder

## Workflow in steps

1. **Analyse**, identify: type of application (stateless or stateful), external dependencies, target environments, ingress, secret and HPA needs.
2. **Scaffold**, `helm create mychart` then clean out the unused examples.
3. **Model `values.yaml`**, define defaults that work in dev with no override. Anything varying per environment becomes a value.
4. **Write the templates**, use `_helpers.tpl` for labels and names; add `checksum/config` to force a rollout when a ConfigMap changes.
5. **Validate locally**, `helm lint`, `helm template`, `helm diff` (plugin) before any push.
6. **Deploy per environment**, `helm upgrade --install` with `-f values-prod.yaml` and `--set image.tag=$TAG`.
7. **Post-deploy operations**, check `helm status`, inspect the logs, keep `helm rollback` ready.

## Typical structure

```
mychart/
├── Chart.yaml              # Metadata and dependencies
├── values.yaml             # Defaults (dev fonctionnel sans override)
├── values-staging.yaml
├── values-prod.yaml
├── templates/
│   ├── _helpers.tpl        # reusable includes (labels, fullname and so on)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── configmap.yaml
│   ├── secret.yaml         # ou ExternalSecret si ESO
│   ├── serviceaccount.yaml
│   └── NOTES.txt           # printed after install
└── charts/                 # downloaded dependencies
```

## Chart.yaml

```yaml
apiVersion: v2
name: payment-api
description: API de gestion des paiements
type: application          # ou "library" pour un chart utilitaire
version: 1.3.0             # SemVer of the chart, independent of the app
appVersion: "3.2.0"        # version de l'image applicative
dependencies:
  - name: cloudnative-pg
    version: "0.x.x"               # check with: helm search repo cnpg
    repository: "https://cloudnative-pg.github.io/charts"
    condition: cloudnative-pg.enabled   # can be disabled through values
```

> **Bitnami pitfall**: most tutorials online declare their dependencies on
> `oci://registry-1.docker.io/bitnamicharts`. Broadcom removed that public catalogue on
> 29 September 2025: versioned charts moved behind a subscription, and only 44
> development-only images tagged `latest` remain. Those examples fail at
> `helm dependency update`. Alternatives: the official chart of the upstream project when one exists,
> otherwise the maintained forks (Chainguard, RapidFort).

> **Criterion**: bump `version` on every template change; bump `appVersion` on every application release.

## `_helpers.tpl`, minimal base

```yaml
{{- define "mychart.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mychart.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

## Deployment, reference template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      serviceAccountName: {{ include "mychart.fullname" . }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
          envFrom:
            - configMapRef:
                name: {{ include "mychart.fullname" . }}
          {{- if .Values.secret.enabled }}
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "mychart.fullname" . }}
                  key: db-password
          {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
```

## `values.yaml`, complete defaults

```yaml
replicaCount: 1   # override to 2 or more in production

image:
  repository: myregistry.azurecr.io/payment-api
  tag: ""          # vide = Chart.AppVersion
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false   # switched on by values-prod.yaml
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: api.company.com
      paths:
        - path: /
          pathType: Prefix

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

probes:
  liveness:
    path: /health/live
  readiness:
    path: /health/ready

secret:
  enabled: false

cloudnative-pg:
  enabled: false   # enable locally when needed
```

## Essential commands

```bash
# Scaffolding
helm create mychart

# Validation locale (toujours avant push)
helm lint mychart
helm template myrelease mychart -f values-prod.yaml | kubectl apply --dry-run=client -f -

# Deployment
helm upgrade --install myrelease ./mychart \
  -f values-prod.yaml \
  --set image.tag=v3.2.0 \
  --namespace prod \
  --create-namespace \
  --atomic \           # automatic rollback on failure
  --timeout 5m

# Diff before upgrading (requires the helm-diff plugin)
helm diff upgrade myrelease ./mychart -f values-prod.yaml --set image.tag=v3.2.0

# Rollback
helm rollback myrelease 1   # revision 1

# Dependencies
helm dependency update mychart

# Inspect a release
helm status myrelease -n prod
helm get values myrelease -n prod
helm history myrelease -n prod

# OCI registry (Helm 3.8+)
helm push mychart-1.3.0.tgz oci://myregistry.azurecr.io/charts
helm install myrelease oci://myregistry.azurecr.io/charts/mychart --version 1.3.0
```

## Decision criteria

| Need | Recommended solution |
|---|---|
| Sensitive secret in production | ExternalSecret (ESO) or Vault Agent Injector, never a plaintext `kind: Secret` |
| Multiple environments | `values-<env>.yaml` plus `-f` at install time, rather than heavy conditional templating |
| Local database dependency in dev | `cloudnative-pg.enabled: true` in `values-dev.yaml` |
| Stateful application (database, Kafka) | `StatefulSet` plus PVC in the template, not `Deployment` |
| Chart reused across teams | A `library` chart in a shared OCI registry |
| Zero-downtime rollout | `strategy.type: RollingUpdate` plus `minReadySeconds` and correct probes |

## Anti-patterns and pitfalls

- **`image.tag: latest`**, not reproducible. Always pass `--set image.tag=$CI_SHA`.
- **Plaintext secrets in values.yaml**, never commit credentials; use ESO, Vault, or `--set secret.password=$VAR` from CI.
- **`helm install` without `--atomic`**, leaves the release in a `FAILED` state; prefer `--atomic` in CI/CD.
- **Omitting `checksum/config`**, without that annotation the pod does not restart when the ConfigMap changes.
- **Forgetting `helm dependency update`**, an empty `charts/` directory makes the install fail silently.
- **Badly separated versioning**, do not keep `version` (chart) and `appVersion` (image) in sync: they move independently.
- **Over-conditional templates**, `{{- if .Values.featureX }}…{{- end }}` everywhere makes the chart unreadable; prefer separate charts or Kustomize overlays for major variants.
- **No `NOTES.txt`**, which deprives users of the post-install instructions.

## Good practice for 2026

- Publish to an **OCI registry** (ACR, ECR, GHCR) rather than a classic HTTP chart repository.
- Use **`helm diff`** in CI to produce a readable summary in the pull request before merge.
- Pair it with **`ct` (chart-testing)** for linting and automated integration tests.
- Enable a **`NetworkPolicy`** by default in the chart to limit the blast radius.
- Generate the **documentation** of the values with `helm-docs` (`# -- description` annotations).
- Prefer **`--atomic --timeout`** in CD to guarantee an automatic rollback when a rollout fails.
