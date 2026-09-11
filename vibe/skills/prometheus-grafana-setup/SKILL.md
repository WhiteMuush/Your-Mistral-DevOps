---
name: prometheus-grafana-setup
description: Setting up Prometheus and Grafana for application and infrastructure monitoring, metrics, alerts, dashboards, scraping, PromQL and Alertmanager. Use it when the user sets up monitoring, configures alerts or builds Grafana dashboards. Also triggers on "Prometheus", "Grafana", "monitoring", "metrics", "alerting", "Grafana dashboard", "PromQL", "scraping".
user-invocable: true
---

# Prometheus and Grafana setup

## Workflow in five steps

### 1. Choose the deployment strategy

| Context | Recommended option |
|---|---|
| Kubernetes | `kube-prometheus-stack` (Helm) |
| Docker Compose (dev and staging) | Multi-service Compose |
| Bare metal or VM | Binaries plus systemd |
| Grafana Cloud | Alloy agent into the managed cloud |

```bash
# Option Kubernetes (tout-en-un : Prometheus + Grafana + AlertManager + exporters)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=changeme \
  --set prometheus.prometheusSpec.retention=15d
```

```yaml
# docker-compose.yml (dev)
services:
  prometheus:
    image: prom/prometheus:v3.13.0   # branche LTS
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./alerts:/etc/prometheus/alerts
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=15d
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:13.2.0
    environment:
      GF_SECURITY_ADMIN_PASSWORD: changeme
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    ports: ["3000:3000"]

  alertmanager:
    image: prom/alertmanager:v0.34.0
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports: ["9093:9093"]

volumes:
  grafana-data:
```

### 2. Instrument the application

**Metric types, when to use which:**

| Type | Characteristic | Concrete example |
|---|---|---|
| Counter | Monotonically increasing | Total requests, errors |
| Gauge | Free to move either way | Active connections, RAM used |
| Histogram | Buckets plus count and sum | Latency (p50, p95, p99) |
| Summary | Quantiles computed client side | Latency when no aggregation is needed |

> Prefer a Histogram over a Summary when the metrics will be aggregated across several instances.

```csharp
// dotnet add package prometheus-net.AspNetCore
// Program.cs
app.UseHttpMetrics();
app.MapMetrics(); // expose /metrics

// Custom metrics
private static readonly Counter PaymentsTotal = Metrics
    .CreateCounter("payments_total", "Total paiements",
        new CounterConfiguration { LabelNames = ["status", "currency"] });

private static readonly Histogram PaymentDuration = Metrics
    .CreateHistogram("payment_duration_seconds", "Payment duration",
        new HistogramConfiguration
        {
            // Buckets exponentiels : 10ms → ~10s
            Buckets = Histogram.ExponentialBuckets(0.01, 2, 10)
        });

// Utilisation
PaymentsTotal.WithLabels("success", "TND").Inc();
using (PaymentDuration.NewTimer()) { /* business call */ }
```

```go
// Go, github.com/prometheus/client_golang
var requestDuration = promauto.NewHistogramVec(
    prometheus.HistogramOpts{
        Name:    "http_request_duration_seconds",
        Help:    "Duration of HTTP requests",
        Buckets: prometheus.DefBuckets,
    },
    []string{"method", "path", "status"},
)
```

### 3. Configure Prometheus scraping

```yaml
# prometheus.yml
global:
  scrape_interval: 15s       # intervalle de collecte
  evaluation_interval: 15s   # evaluation of the alerting rules

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - "alerts/*.yml"

scrape_configs:
  # Application custom
  - job_name: payment-api
    metrics_path: /metrics
    static_configs:
      - targets: ["payment-api:8080"]
    relabel_configs:
      - target_label: env
        replacement: production

  # Kubernetes auto-discovery
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: $1

  # Exporter node (infra)
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]
```

### 4. Operational PromQL queries

```promql
# --- Taux d'erreur 5xx (%) sur 5 min ---
100 * sum(rate(http_requests_total{status=~"5.."}[5m]))
  / sum(rate(http_requests_total[5m]))

# --- Latence p99 par service ---
histogram_quantile(0.99,
  sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
)

# --- Requests per second by endpoint ---
topk(10, sum by (path) (rate(http_requests_total[5m])))

# --- CPU (node-exporter) ---
100 - avg by (instance) (
  irate(node_cpu_seconds_total{mode="idle"}[5m])
) * 100

# --- RAM disponible (%) ---
100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# --- Pods not in a Ready state (Kubernetes) ---
kube_pod_status_ready{condition="false"} == 1
```

### 5. Alerts and Alertmanager

```yaml
# alerts/slo-alerts.yml
groups:
  - name: slo
    rules:
      - alert: ErrorRateTooHigh
        expr: |
          (
            sum(rate(http_requests_total{status=~"5..",job="payment-api"}[5m]))
            / sum(rate(http_requests_total{job="payment-api"}[5m]))
          ) > 0.01
        for: 5m
        labels:
          severity: critical
          team: backend
        annotations:
          summary: "Taux d'erreur > 1% sur payment-api"
          description: "Erreur actuelle : {{ $value | humanizePercentage }}"
          runbook: "https://wiki.internal/runbooks/payment-api"

      - alert: LatencyP99High
        expr: |
          histogram_quantile(0.99,
            sum by (le) (rate(http_request_duration_seconds_bucket{job="payment-api"}[5m]))
          ) > 1.0
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "p99 latence > 1s"
```

```yaml
# alertmanager.yml
route:
  group_by: [alertname, team]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: slack-critical
  routes:
    - match:
        severity: warning
      receiver: slack-warning

receivers:
  - name: slack-critical
    slack_configs:
      - api_url: "https://hooks.slack.com/services/XXX"
        channel: "#alerts-critical"
        title: "{{ .GroupLabels.alertname }}"
        text: "{{ range .Alerts }}{{ .Annotations.description }}{{ end }}"
  - name: slack-warning
    slack_configs:
      - api_url: "https://hooks.slack.com/services/XXX"
        channel: "#alerts-warning"
```

## Grafana dashboards, good practice

**The four Golden Signals (Google SRE), to be covered every time:**
- **Latency**: p50, p95, p99 through `histogram_quantile`
- **Traffic**: requests per second through `rate(…[5m])`
- **Errors**: rate of 5xx responses and exceptions
- **Saturation**: CPU, RAM, pool connections

**Provisioning as code (recommended in production):**
```yaml
# grafana/provisioning/dashboards/default.yaml
apiVersion: 1
providers:
  - name: default
    type: file
    options:
      path: /etc/grafana/dashboards
```
Put the exported JSON files in `/etc/grafana/dashboards/`, they are reloaded without a restart.

**Community dashboards worth importing (Grafana ID):**
- `1860`, Node Exporter Full
- `315`, Kubernetes cluster
- `13659`, ASP.NET Core
- `11159`, RabbitMQ

## Guardrails and anti-patterns

| Anti-pattern | Consequence | Fix |
|---|---|---|
| High-cardinality label (for example `user_id`) | The TSDB explodes and Prometheus OOMs | Use only stable labels (env, service, status) |
| `scrape_interval` under 10s on many targets | Network and storage overload | 15s by default, 30s for stable infrastructure |
| Alerts without `for` | False positives on a short spike | Always `for: 2m` at minimum |
| Histograms with default buckets | Buckets unsuited to the real latency | Size the buckets around the target SLO |
| No `runbook` in the annotations | Oncall without context | Always add a link to the procedure |
| Grafana without provisioning as code | Dashboards lost on restart | Version the JSON in the repository |
| Infinite retention | Disk full | `--storage.tsdb.retention.time=30d` or `--storage.tsdb.retention.size=50GB` |

## Quick validation

```bash
# Check the Prometheus configuration
docker run --rm -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus:v3.13.0 promtool check config /etc/prometheus/prometheus.yml

# Check the alerting rules
promtool check rules alerts/*.yml

# Test a PromQL rule
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(http_requests_total[5m])' | jq .

# See the firing alerts
curl -s http://localhost:9093/api/v2/alerts | jq '[.[] | {name:.labels.alertname, state:.status.state}]'
```
