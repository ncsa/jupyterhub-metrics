# Helm Chart for JupyterHub Metrics

This document provides an overview of the complete Helm chart implementation for the JupyterHub Metrics monitoring system.

## Overview

The Helm chart has been fully converted from the manual Kubernetes deployment scripts to a production-ready, templated Helm chart. All configuration from `.env` variables has been mapped to Helm `values.yaml`.

## Chart Location

```text
/chart/
├── Chart.yaml                  # Chart metadata and version
├── values.yaml                 # Default configuration values
├── README.md                   # Comprehensive Helm chart documentation
├── update-templates.sh         # Script to sync source files into chart
├── files/                      # Source files (synced from project root)
└── templates/                  # Helm Go templates
    ├── _helpers.tpl           # Helper functions
    ├── namespace.yaml         # Namespace creation
    ├── secrets.yaml           # Secret generation from values
    ├── configmap-*.yaml       # Configuration maps (5 files)
    ├── rbac-*.yaml            # RBAC resources (3 files)
    ├── statefulset-timescaledb.yaml
    ├── deployment-grafana.yaml
    ├── deployment-collector.yaml
    └── ingress.yaml
```

## Configuration Mapping

### .env Variables → Helm Values

All variables from the original `.env` file are now available in `values.yaml`:

| Original `.env` | Helm Value Path | Type | Description |
|---|---|---|---|
| `DB_HOST` | `db.host` | String | Database hostname (auto-constructed if using internal DB) |
| `DB_PORT` | `db.port` | Integer | Database port |
| `DB_NAME` | `db.name` | String | Database name |
| `DB_USER` | `db.user` | String | Database username |
| `DB_PASSWORD` | `db.password` | Secret | Database password |
| `GRAFANA_ADMIN_USER` | `grafana.adminUser` | String | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | `grafana.adminPassword` | Secret | Grafana admin password |
| `GRAFANA_PORT` | `grafana.port` | Integer | Grafana service port |
| `COLLECTION_INTERVAL` | `collector.interval` | String | Collection frequency in seconds |
| `KUBECTL_CONTEXT` | (removed) | N/A | Not needed in Helm (uses in-cluster auth) |
| `NAMESPACE` | `jupyterhub.namespace` | String | Target JupyterHub namespace |
| `TIMESCALEDB_STORAGE_SIZE` | `timescaledb.storage.size` | String | Database storage size |
| `TIMESCALEDB_STORAGE_CLASS` | `timescaledb.storage.storageClass` | String | Storage class name |
| `TIMESCALEDB_MEMORY_REQUEST` | `timescaledb.resources.requests.memory` | String | Memory request |
| `TIMESCALEDB_MEMORY_LIMIT` | `timescaledb.resources.limits.memory` | String | Memory limit |
| `TIMESCALEDB_CPU_REQUEST` | `timescaledb.resources.requests.cpu` | String | CPU request |
| `TIMESCALEDB_CPU_LIMIT` | `timescaledb.resources.limits.cpu` | String | CPU limit |
| `GRAFANA_USE_PVC` | `grafana.persistence.enabled` | Boolean | Use persistent volume |
| `GRAFANA_STORAGE_SIZE` | `grafana.persistence.size` | String | Grafana storage size |
| `GRAFANA_STORAGE_CLASS` | `grafana.persistence.storageClass` | String | Grafana storage class |
| `DEPLOY_INGRESS` | `ingress.enabled` | Boolean | Enable ingress |
| `INGRESS_HOST` | `ingress.host` | String | Ingress hostname |
| `INGRESS_TLS_SECRET` | `ingress.tls.secretName` | String | TLS secret name |
| `CERT_MANAGER_ISSUER` | `ingress.tls.certManagerIssuer` | String | cert-manager issuer |
| `COLLECTOR_MEMORY_REQUEST` | `collector.resources.requests.memory` | String | Collector memory request |
| `COLLECTOR_MEMORY_LIMIT` | `collector.resources.limits.memory` | String | Collector memory limit |
| `COLLECTOR_CPU_REQUEST` | `collector.resources.requests.cpu` | String | Collector CPU request |
| `COLLECTOR_CPU_LIMIT` | `collector.resources.limits.cpu` | String | Collector CPU limit |
| `POD_LABEL_SELECTOR` | `jupyterhub.podLabelSelector` | String | Pod selector for JupyterHub |
| `DEBUG` | `global.debug` | Boolean | Debug mode |

## Key Features

### 1. All-in-One Templating

Every Kubernetes resource is now a template:

- ✅ Namespace
- ✅ Secrets (auto-generated from values)
- ✅ ConfigMaps (5 different configurations)
- ✅ RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- ✅ StatefulSet (TimescaleDB)
- ✅ Deployments (Grafana, Collector)
- ✅ Services (ClusterIP)
- ✅ PersistentVolumeClaims (conditional)
- ✅ Ingress (conditional)

### 2. Source File Synchronization

The `update-templates.sh` script automatically syncs source files into the chart:

```bash
./chart/update-templates.sh
```

This keeps chart templates in sync with:

- `init-db.sql` → `chart/files/init-db.sql`
- `collector.sh` → `chart/files/collector.sh`
- `grafana/provisioning/` → `chart/files/grafana/provisioning/`
- `grafana/dashboards/` → `chart/files/grafana/dashboards/`

### 3. Helper Functions

The `_helpers.tpl` includes utility functions:

- `jupyterhub-metrics.name` - Chart name
- `jupyterhub-metrics.fullname` - Full release name
- `jupyterhub-metrics.labels` - Standard labels
- `jupyterhub-metrics.selectorLabels` - Pod selector labels
- `jupyterhub-metrics.serviceAccountName` - Service account name
- `jupyterhub-metrics.db.host` - Database host (internal or external)
- `jupyterhub-metrics.db.passwordSecret` - Secret reference
- And more...

### 4. External Secret Support

Optionally use external secrets instead of embedding in values:

```yaml
secrets:
  externalSecretEnabled: true
  externalSecretName: my-external-secret
  externalSecretDbPasswordKey: db-password
  externalSecretGrafanaPasswordKey: grafana-password
```

### 5. Conditional Features

Features can be enabled/disabled:

```yaml
global:
  timescaledbEnabled: true
  grafanaEnabled: true
  collectorEnabled: true
  ingressEnabled: false

ingress:
  enabled: false
  tls:
    enabled: false
```

### 6. Advanced Configuration

Node affinity, tolerations, security contexts, and more:

```yaml
advanced:
  nodeSelector:
    node-role: monitoring
  tolerations:
    - key: monitoring
      operator: Equal
      value: "true"
      effect: NoSchedule
  affinity: {}
  priorityClassName: ""
```

## Installation

### Quick Start

```bash
helm install jupyterhub-metrics ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)"
```

### With Custom Values

```bash
helm install jupyterhub-metrics ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  -f values-prod.yaml
```

## Workflow

### 1. Deploy

```bash
# First time: ensure source files are in chart
./chart/update-templates.sh

# Install
helm install jupyterhub-metrics ./chart --namespace jupyterhub-metrics -f values.yaml
```

### 2. Update Source Files

When you modify `collector.sh`, `init-db.sql`, or dashboards:

```bash
# Sync changes into chart
./chart/update-templates.sh

# Commit
git add chart/files/
git commit -m "chore: update helm templates from source"

# Upgrade deployment
helm upgrade jupyterhub-metrics ./chart --namespace jupyterhub-metrics
```

### 3. Modify Configuration

To change settings:

```bash
# Edit values file
nano values-prod.yaml

# Upgrade
helm upgrade jupyterhub-metrics ./chart \
  --namespace jupyterhub-metrics \
  -f values-prod.yaml
```

## Architecture

### Template File Organization

```text
templates/
├── Namespace & RBAC
│   ├── namespace.yaml
│   ├── rbac-serviceaccount.yaml
│   ├── rbac-clusterrole.yaml
│   └── rbac-clusterrolebinding.yaml
│
├── Secrets & Config
│   ├── secrets.yaml
│   ├── configmap-init-db.yaml
│   ├── configmap-grafana-datasources.yaml
│   ├── configmap-grafana-provisioning.yaml
│   ├── configmap-grafana-dashboards.yaml
│   └── configmap-collector.yaml
│
├── Stateful Services
│   └── statefulset-timescaledb.yaml
│       └── Service (TimescaleDB)
│
├── Deployments
│   ├── deployment-grafana.yaml
│   │   ├── Deployment
│   │   ├── Service
│   │   └── PVC (if persistence.enabled)
│   │
│   └── deployment-collector.yaml
│       └── Deployment
│
└── Ingress
    └── ingress.yaml
```

### Value Hierarchy

1. **Default values** in `values.yaml`
2. **Override with** `-f values-prod.yaml`
3. **Override with** `--set key=value` flags

Example:

```bash
helm install jupyterhub-metrics ./chart \
  -f values-prod.yaml \  # First override
  --set db.password="secret"  # Final override
```

## Helm Chart Benefits

Using Helm provides significant advantages over manual Kubernetes deployments:

**Benefits:**

- ✅ Industry-standard templating with Go templates
- ✅ Reusable across multiple environments
- ✅ Easy to customize via values.yaml
- ✅ Built-in validation with `helm lint`
- ✅ Easy upgrades and rollbacks
- ✅ GitOps-ready
- ✅ Package versioning and distribution

**Quick Workflow:**

```bash
# Sync source files once
./chart/update-templates.sh

# Install with Helm
helm install jupyterhub-metrics ./chart -f values.yaml

# Upgrade as needed
helm upgrade jupyterhub-metrics ./chart

# Rollback if needed
helm rollback jupyterhub-metrics
```

## Troubleshooting

### Helm Lint

```bash
helm lint ./chart
```

### Dry Run

```bash
helm install jupyterhub-metrics ./chart --dry-run --debug
```

### Template Rendering

```bash
helm template jupyterhub-metrics ./chart
```

### Check Current Values

```bash
helm get values jupyterhub-metrics -n jupyterhub-metrics
```

## Advanced Topics

### Multiple Environments

```bash
# values-dev.yaml
helm install jupyterhub-metrics-dev ./chart \
  --namespace jupyterhub-metrics-dev \
  -f values-dev.yaml

# values-prod.yaml
helm install jupyterhub-metrics-prod ./chart \
  --namespace jupyterhub-metrics-prod \
  -f values-prod.yaml
```

### GitOps Integration

```bash
# ArgoCD / Flux example
apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  name: jupyterhub-metrics
spec:
  chart:
    repository: https://github.com/ncsa/jupyterhub-metrics
    name: chart
  values:
    db:
      password: !terraform/remote_state db_password
    grafana:
      adminPassword: !terraform/remote_state grafana_password
```

### Secrets Management

Use Sealed Secrets or External Secrets Operator:

```bash
# Create and seal secret
kubectl create secret generic jupyterhub-metrics-creds \
  --from-literal=db-password="..." \
  --dry-run=client \
  -o yaml | kubeseal > sealed-secret.yaml

# Apply sealed secret
kubectl apply -f sealed-secret.yaml
```

## Documentation

- **Chart README**: See `chart/README.md` for complete documentation
- **Main README**: See `README.md` for project overview
- **Security**: See `SECURITY.md` for security best practices

## Support

For issues with the Helm chart:

1. Run `helm lint ./chart` to check syntax
2. Run `helm template` to preview rendered resources
3. Check logs: `kubectl logs -n jupyterhub-metrics`
4. Review values: `helm get values <release-name>`

## What's Next

After deploying the Helm chart:

1. Configure persistent storage if needed
2. Set up ingress with TLS certificates
3. Configure monitoring and alerting
4. Plan backup and disaster recovery
5. Document your customizations

## Additional Resources

- [Helm Official Documentation](https://helm.sh/docs/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/overview/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [Grafana Documentation](https://grafana.com/docs/)
