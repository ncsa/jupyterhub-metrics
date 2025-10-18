# JupyterHub Metrics

A Helm chart for Kubernetes that deploys a complete JupyterHub metrics monitoring system with TimescaleDB, Grafana, and an automated metrics collector.

## Prerequisites

- Kubernetes 1.20+
- Helm 3.0+
- Sufficient cluster resources:
  - Memory: At least 2Gi available
  - Storage: Persistent volume support for database

## Installation

### Add the Helm Repository

```bash
# If using a remote repository (update with your actual repository URL)
helm repo add jupyterhub-metrics https://example.com/charts
helm repo update
```

### Install the Chart

```bash
helm install my-release jupyterhub-metrics/jupyterhub-metrics \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)"
```

Or from local source:

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)"
```

### Install with Custom Values File

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  -f values.yaml
```

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```bash
helm uninstall my-release --namespace jupyterhub-metrics
```

To also delete the persistent volumes:

```bash
helm uninstall my-release --namespace jupyterhub-metrics
kubectl delete pvc -n jupyterhub-metrics --all
```

## Configuration

The following table lists the configurable parameters of the JupyterHub Metrics chart and their default values.

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.debug` | Enable debug mode | `false` |

### Database Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `db.name` | Database name | `jupyterhub_metrics` |
| `db.user` | Database username | `metrics_user` |
| `db.password` | Database password (required) | `""` |
| `db.port` | Database port | `5432` |
| `db.external` | Use external database | `false` |
| `db.externalHost` | External database hostname | `""` |
| `db.externalPort` | External database port | `5432` |

### TimescaleDB

| Parameter | Description | Default |
|-----------|-------------|---------|
| `timescaledb.enabled` | Enable TimescaleDB deployment | `true` |
| `timescaledb.image.repository` | TimescaleDB image repository | `timescale/timescaledb` |
| `timescaledb.image.tag` | TimescaleDB image tag | `latest-pg15` |
| `timescaledb.image.pullPolicy` | TimescaleDB image pull policy | `IfNotPresent` |
| `timescaledb.serviceName` | TimescaleDB service name | `timescaledb` |
| `timescaledb.storage.size` | Storage size | `20Gi` |
| `timescaledb.storage.storageClass` | Storage class name | `""` |
| `timescaledb.storage.accessMode` | Storage access mode | `ReadWriteOnce` |
| `timescaledb.resources.requests.memory` | Memory request | `512Mi` |
| `timescaledb.resources.requests.cpu` | CPU request | `250m` |
| `timescaledb.resources.limits.memory` | Memory limit | `2Gi` |
| `timescaledb.resources.limits.cpu` | CPU limit | `1000m` |
| `timescaledb.livenessProbe.initialDelaySeconds` | Liveness probe initial delay | `30` |
| `timescaledb.livenessProbe.periodSeconds` | Liveness probe period | `10` |
| `timescaledb.livenessProbe.timeoutSeconds` | Liveness probe timeout | `5` |
| `timescaledb.livenessProbe.failureThreshold` | Liveness probe failure threshold | `3` |
| `timescaledb.readinessProbe.initialDelaySeconds` | Readiness probe initial delay | `10` |
| `timescaledb.readinessProbe.periodSeconds` | Readiness probe period | `5` |
| `timescaledb.readinessProbe.timeoutSeconds` | Readiness probe timeout | `3` |
| `timescaledb.readinessProbe.failureThreshold` | Readiness probe failure threshold | `3` |

### Grafana

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.enabled` | Enable Grafana deployment | `true` |
| `grafana.replicas` | Number of Grafana replicas | `1` |
| `grafana.adminUser` | Grafana admin username | `admin` |
| `grafana.adminPassword` | Grafana admin password (required) | `""` |
| `grafana.image.repository` | Grafana image repository | `grafana/grafana` |
| `grafana.image.tag` | Grafana image tag | `latest` |
| `grafana.image.pullPolicy` | Grafana image pull policy | `IfNotPresent` |
| `grafana.port` | Grafana service port | `3000` |
| `grafana.plugins` | List of Grafana plugins to install | `["grafana-clock-panel"]` |
| `grafana.persistence.enabled` | Enable persistent volume for Grafana | `false` |
| `grafana.persistence.size` | Persistent volume size | `5Gi` |
| `grafana.persistence.storageClass` | Storage class name | `""` |
| `grafana.persistence.accessMode` | Storage access mode | `ReadWriteOnce` |
| `grafana.resources.requests.memory` | Memory request | `128Mi` |
| `grafana.resources.requests.cpu` | CPU request | `100m` |
| `grafana.resources.limits.memory` | Memory limit | `512Mi` |
| `grafana.resources.limits.cpu` | CPU limit | `500m` |
| `grafana.livenessProbe.initialDelaySeconds` | Liveness probe initial delay | `30` |
| `grafana.livenessProbe.periodSeconds` | Liveness probe period | `10` |
| `grafana.livenessProbe.timeoutSeconds` | Liveness probe timeout | `5` |
| `grafana.livenessProbe.failureThreshold` | Liveness probe failure threshold | `3` |
| `grafana.readinessProbe.initialDelaySeconds` | Readiness probe initial delay | `10` |
| `grafana.readinessProbe.periodSeconds` | Readiness probe period | `5` |
| `grafana.readinessProbe.timeoutSeconds` | Readiness probe timeout | `3` |
| `grafana.readinessProbe.failureThreshold` | Readiness probe failure threshold | `3` |

### Metrics Collector

| Parameter | Description | Default |
|-----------|-------------|---------|
| `collector.enabled` | Enable metrics collector | `true` |
| `collector.interval` | Collection interval in seconds | `300` |
| `collector.image.repository` | Collector base image repository | `alpine` |
| `collector.image.tag` | Collector base image tag | `3.19` |
| `collector.image.pullPolicy` | Collector image pull policy | `IfNotPresent` |
| `collector.resources.requests.memory` | Memory request | `128Mi` |
| `collector.resources.requests.cpu` | CPU request | `100m` |
| `collector.resources.limits.memory` | Memory limit | `512Mi` |
| `collector.resources.limits.cpu` | CPU limit | `500m` |

### JupyterHub Target

| Parameter | Description | Default |
|-----------|-------------|---------|
| `jupyterhub.namespace` | Kubernetes namespace where JupyterHub is deployed | `jupyterhub` |
| `jupyterhub.podLabelSelector` | Label selector for JupyterHub singleuser pods | `component=singleuser-server` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress for Grafana | `false` |
| `ingress.className` | Ingress class name | `nginx` |
| `ingress.host` | Hostname for Grafana access | `metrics.example.com` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.tls.enabled` | Enable TLS/HTTPS | `false` |
| `ingress.tls.secretName` | TLS certificate secret name | `grafana-tls` |
| `ingress.tls.certManagerIssuer` | cert-manager issuer name | `""` |

### RBAC

| Parameter | Description | Default |
|-----------|-------------|---------|
| `rbac.create` | Create RBAC resources | `true` |
| `rbac.serviceAccountName` | Service account name | `metrics-collector` |
| `rbac.clusterRoleName` | Cluster role name | `jupyterhub-metrics-reader` |

### Secrets

| Parameter | Description | Default |
|-----------|-------------|---------|
| `secrets.externalSecretEnabled` | Use external secret | `false` |
| `secrets.externalSecretName` | External secret name | `""` |
| `secrets.externalSecretDbPasswordKey` | External secret DB password key | `db-password` |
| `secrets.externalSecretGrafanaPasswordKey` | External secret Grafana password key | `grafana-password` |

### Security Context & Policies

| Parameter | Description | Default |
|-----------|-------------|---------|
| `security.podSecurityStandard` | Pod Security Standards level (baseline/restricted) | `restricted` |
| `security.networkPolicyEnabled` | Enable NetworkPolicy for traffic restriction | `false` |
| `security.podSecurityPolicyEnabled` | Enable Pod Security Policy (legacy) | `false` |

### Advanced Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `advanced.namespace` | Namespace for deployment | `jupyterhub-metrics` |
| `advanced.createNamespace` | Create namespace if not exists | `true` |
| `advanced.nodeSelector` | Node selector for pod placement | `{}` |
| `advanced.tolerations` | Pod tolerations | `[]` |
| `advanced.affinity` | Pod affinity rules | `{}` |
| `advanced.priorityClassName` | Priority class name | `""` |
| `advanced.kubeWaitTimeout` | Resource creation timeout (seconds) | `300` |

## Examples

### Basic Installation with Required Parameters

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password"
```

### Installation with Custom Database

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password" \
  --set db.external=true \
  --set db.externalHost="postgresql.example.com" \
  --set db.externalPort="5432"
```

### Installation with Ingress and TLS

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password" \
  --set ingress.enabled=true \
  --set ingress.host="metrics.example.com" \
  --set ingress.tls.enabled=true \
  --set ingress.tls.certManagerIssuer="letsencrypt-prod"
```

### Installation with Persistent Grafana Storage

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password" \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size="10Gi"
```

### Installation Using Values File

```bash
# Create values-prod.yaml
cat > values-prod.yaml << EOF
db:
  password: "my-secure-database-password"
grafana:
  adminPassword: "my-secure-grafana-password"
  replicas: 2
  persistence:
    enabled: true
    size: 10Gi
ingress:
  enabled: true
  host: metrics.example.com
  tls:
    enabled: true
    certManagerIssuer: letsencrypt-prod
timescaledb:
  storage:
    size: 100Gi
    storageClass: fast-ssd
EOF

helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  -f values-prod.yaml
```

### Installation on Security-Enabled Clusters

For clusters with Pod Security Standards or Network Policies enabled:

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)" \
  --set security.podSecurityStandard=restricted \
  --set security.networkPolicyEnabled=true
```

This will:
- Enforce Pod Security Standards (restricted level)
- Enable NetworkPolicies to restrict pod-to-pod traffic
- Allow only necessary communication paths:
  - Grafana → TimescaleDB (port 5432)
  - Collector → TimescaleDB (port 5432)
  - External traffic → Grafana (port 3000)

## Upgrading

To upgrade an existing release:

```bash
helm upgrade my-release ./chart \
  --namespace jupyterhub-metrics \
  -f values.yaml
```

After updating source files (init-db.sql, collector.sh, dashboards), sync them into the chart:

```bash
./update-templates.sh
helm upgrade my-release ./chart --namespace jupyterhub-metrics
```

## Verification

### Check Installation Status

```bash
helm status my-release --namespace jupyterhub-metrics
```

### List All Deployed Resources

```bash
kubectl get all -n jupyterhub-metrics
```

### View Logs

```bash
# TimescaleDB logs
kubectl logs -n jupyterhub-metrics -l app.kubernetes.io/component=timescaledb

# Grafana logs
kubectl logs -n jupyterhub-metrics -l app.kubernetes.io/component=grafana

# Collector logs
kubectl logs -n jupyterhub-metrics -l app.kubernetes.io/component=collector
```

### Access Grafana

Port forward to Grafana:

```bash
kubectl port-forward -n jupyterhub-metrics svc/my-release-grafana 3000:3000
```

Then access at `http://localhost:3000` with the admin credentials set during installation.

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n jupyterhub-metrics
kubectl describe pod <pod-name> -n jupyterhub-metrics
```

### Database Connection Issues

```bash
# Port forward to database
kubectl port-forward -n jupyterhub-metrics svc/timescaledb 5432:5432

# Test connection
PGPASSWORD="$DB_PASSWORD" psql -h localhost -U metrics_user -d jupyterhub_metrics -c "SELECT 1"
```

### Init Job Failed

Check the init job logs:

```bash
kubectl get jobs -n jupyterhub-metrics
kubectl logs -n jupyterhub-metrics job/my-release-init-db
```

### Helm Lint

Validate chart syntax:

```bash
helm lint ./chart
```

### Dry Run

Preview resources before installation:

```bash
helm install my-release ./chart --dry-run --debug
```

## Updating Source Files

When you update the source files in the project root (init-db.sql, collector.sh, Grafana dashboards), synchronize them into the chart:

```bash
./chart/update-templates.sh
```

Then commit and deploy:

```bash
git add chart/files/
git commit -m "chore: update helm chart templates"
helm upgrade my-release ./chart --namespace jupyterhub-metrics
```

## Chart Components

### TimescaleDB StatefulSet
- Persistent time-series database
- Automatic initialization on first deployment (post-install hook)
- Configured with appropriate storage and resource limits

### Grafana Deployment
- Dashboard visualization
- Pre-configured TimescaleDB datasource
- Optional persistent storage for Grafana data

### Metrics Collector Deployment
- Collects container metrics from Kubernetes
- Stores data in TimescaleDB
- Configured with RBAC for pod access

### RBAC
- Service account for collector
- Cluster role with permissions to read pods
- Cluster role binding

### Ingress (Optional)
- External access to Grafana
- TLS support with cert-manager integration
- Configurable for different ingress controllers

## Related Documentation

- [Project README](../README.md)
- [Security Configuration](../SECURITY.md)
- [Helm Chart Architecture](../HELM_CHART.md)

## License

This Helm chart is part of the JupyterHub Metrics project and is provided as-is for monitoring JupyterHub deployments.
