---
name: azure-cloud-advisor
description: Advice on architecture and deployment on Azure, App Service, Azure Functions, Container Apps, Azure SQL and cloud good practice. Use it when the user deploys to Azure, picks a cloud service or optimises Azure costs. Also triggers on "Azure", "App Service", "Azure Functions", "Container Apps", "Azure SQL", "Azure deployment", "Azure costs".
user-invocable: true
---

# Azure cloud advisor

## Workflow

1. **Qualify the need**: type of workload (web, event-driven, batch, real time), constraints (SLA, latency, data residency), target monthly budget.
2. **Choose the compute service**: use the matrix below; when it is ambiguous, ask whether the team already knows Kubernetes.
3. **Design the architecture**: network topology (VNet, Private Endpoints), security (Managed Identity, Key Vault), resilience (zones, geo-replication).
4. **Provision**: copyable `az` commands, or Bicep and Terraform.
5. **Optimise**: cost (Reserved, Spot, scale-to-zero), performance (profiling through App Insights), scalability.

---

## Choosing the compute service

| Service | Ideal use | Scaling | Cost profile |
|---|---|---|---|
| **App Service** | Web app or API in .NET, Node, Python | Auto-scale within the plan | Fixed floor from the plan, paid even when idle |
| **Container Apps** | Containerised microservices, Dapr | KEDA, scale-to-zero | Nothing when stopped, grows with traffic |
| **Azure Functions** | Event-driven, triggers (HTTP, Queue, Timer) | Consumption, automatic | Cheapest below the free tier |
| **AKS** | Complex Kubernetes orchestration, multi-tenant | Node autoscaler plus KEDA | The most expensive, nodes are paid continuously |
| **VM and VMSS** | Legacy, total network control | Manual or VMSS | Variable, depends on sizing |

> Absolute figures vary by region, by tier and by commitment, and change far too often
> to be trusted in a cheat sheet. What holds is the relative order:
> check today's number with `az pricing` or the Azure calculator.

### Decision tree

```
Nouveau projet ?
├── Short event-driven processing (under 10 min) → Azure Functions (Consumption)
├── Containerised microservices, variable traffic → Container Apps
├── Web app or REST API, team with no K8s ops    → App Service
├── Advanced Kubernetes needs (CRD, helm, custom networking) → AKS
└── Migration lift-and-shift ou workload GPU   → VM / VMSS

Migration d'un existant ?
├── App .NET monolithique IIS → App Service (Windows plan)
├── Docker Compose existant  → Container Apps
└── Very fine network control (BGP, ASN)        → AKS or VMs
```

---

## Provisioning, copyable commands

### Create a Container Apps Environment and app

```bash
# Variables
RG=rg-myapp-prod
LOCATION=westeurope
ENV=cae-myapp-prod
APP=api-backend

az group create -n $RG -l $LOCATION

az containerapp env create \
  --name $ENV --resource-group $RG --location $LOCATION

az containerapp create \
  --name $APP --resource-group $RG \
  --environment $ENV \
  --image myregistry.azurecr.io/api:latest \
  --target-port 8080 --ingress external \
  --min-replicas 0 --max-replicas 10 \
  --cpu 0.5 --memory 1Gi \
  --registry-server myregistry.azurecr.io \
  --system-assigned                         # Managed Identity
```

### Create an Azure Function (Consumption)

```bash
az storage account create -n stfnmyapp -g $RG -l $LOCATION --sku Standard_LRS
az functionapp create \
  --name fn-myapp-prod --resource-group $RG \
  --storage-account stfnmyapp \
  --consumption-plan-location $LOCATION \
  --runtime dotnet-isolated --runtime-version 10 \
  --functions-version 4 \
  --assign-identity '[system]'
```

### App Service with a staging slot

```bash
az appservice plan create -n plan-myapp -g $RG --sku P2V3 --is-linux
az webapp create -n web-myapp -g $RG --plan plan-myapp --runtime "DOTNETCORE:10.0"
az webapp deployment slot create --name web-myapp -g $RG --slot staging
# Swap zero-downtime :
az webapp deployment slot swap --name web-myapp -g $RG --slot staging
```

---

## Reference architecture, Container Apps microservices

```
Internet
  → Azure Front Door (CDN + WAF)
      → Container Apps Environment (VNet integrated)
            API Gateway (YARP / NGINX)
            ├── Service A  (scale-to-zero, KEDA Queue)
            ├── Service B  (min 1 replica)
            └── Worker     (trigger Azure Service Bus)
      → Azure SQL (Private Endpoint)
      → Azure Cache for Redis (Premium, clustering)
      → Azure Service Bus (Topics + DLQ)
      → Azure Key Vault   (Managed Identity, no secrets in env vars)
      → Application Insights + Log Analytics Workspace
```

---

## Good practice per service

### Azure SQL
- **Elastic Pools** when running more than 3 databases with variable load: 30 to 50 percent saved.
- **Active Geo-Replication** (read) or **Failover Groups** (automatic failover) for high availability.
- Alerts on `DTU percentage > 80 %` or `CPU percent > 85 %`.
- Always connect through Managed Identity, never an SQL password in configuration:
  ```csharp
  // EF Core + Azure Identity
  services.AddDbContext<AppDbContext>(o =>
      o.UseSqlServer(conn, sql => sql.UseAzureIdentityAuthentication()));
  ```

### Azure Key Vault
- **Never** put secrets in App Settings, reference Key Vault instead:
  ```
  @Microsoft.KeyVault(SecretUri=https://kv-myapp.vault.azure.net/secrets/DbPassword/)
  ```
- Access model: RBAC (`Key Vault Secrets User`) rather than Access Policies, which are deprecated.
- Enable **Soft-Delete** (90 days) and **Purge Protection** on production vaults.

### Managed Identities
- System-assigned for ephemeral resources (Functions, Container Apps).
- User-assigned for identities shared between several services.
- Role assignment:
  ```bash
  az role assignment create \
    --assignee <principal-id> \
    --role "Key Vault Secrets User" \
    --scope /subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-myapp
  ```

### Application Insights
- **Always** enable the Connection String, not the InstrumentationKey, which is deprecated.
- Enable **adaptive sampling** in production to keep telemetry costs down.
- Business custom metrics through `TelemetryClient.TrackMetric()` for the functional SLAs.

---

## Cost optimisation

| Lever | Estimated saving | Effort |
|---|---|---|
| Reserved Instances, 1 year (App Service, AKS nodes) | 30 to 45 % | Low |
| Reserved Instances, 3 years | 50 to 65 % | Low |
| Spot VMs (batch, CI workers) | 60 to 90 % | Medium |
| Scale-to-zero (Container Apps, Functions) | Very high, idle costs nothing | None |
| Right-sizing (Azure Advisor) | 20 to 40 % | Medium |
| Azure Dev/Test subscription | 50 to 55 % on VMs | Low |

```bash
# See the Azure Advisor cost recommendations
az advisor recommendation list --category Cost -o table
```

---

## Guardrails, anti-patterns and pitfalls

- **Never store secrets in the environment variables** of App Service or Container Apps: use a Key Vault Reference.
- **Do not use the Consumption tier for Functions needing under 200 ms latency**: cold start runs 1 to 3 seconds there; prefer Premium or Flex Consumption (2024 onwards).
- **Avoid SQL connections using SQL auth** in production: password rotation is expensive, Managed Identity is free and safer.
- **Do not expose Container Apps with `--ingress external` when the API is internal**: use `internal` plus VNet communication.
- **No Shared or Free plan in production**: no SLA, and aggressive CPU throttling.
- **Do not skip Private Endpoints**: without them, Azure SQL and Storage traffic crosses the public internet even from inside a VNet.
- **One Log Analytics Workspace per environment**, never production and dev in the same one: data isolation and control over ingestion costs.
- **AKS without the Cluster Autoscaler means systematic overprovisioning**: always enable `--enable-cluster-autoscaler`.

---

## Production deployment checklist

- [ ] Managed Identity enabled, no plaintext secret
- [ ] Key Vault with Soft-Delete and Purge Protection
- [ ] Private Endpoints on SQL, Redis and Storage
- [ ] Application Insights connected (Connection String)
- [ ] Cost alerts and technical metric alerts configured
- [ ] Auto-scaling (min and max replicas, or App Service scale rules)
- [ ] Staging slot for zero-downtime deployment (App Service)
- [ ] Azure Defender for Cloud enabled on the critical resources
- [ ] Geo-Replication or a Failover Group on Azure SQL when the SLA exceeds 99.9 %
