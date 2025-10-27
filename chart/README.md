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
helm repo add ncsa https://opensource.ncsa.illinois.edu/charts/
helm repo update
```

### Install the Chart

```bash
helm install my-release ncsa/jupyterhub-metrics \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.database.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)"
```

Or from local source:

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.database.password="$(openssl rand -base64 32)" \
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
| `global.timescaledbEnabled` | Enable/disable TimescaleDB component | `true` |
| `global.grafanaEnabled` | Enable/disable Grafana component | `true` |
| `global.collectorEnabled` | Enable/disable metrics collector component | `true` |
| `global.ingressEnabled` | Enable/disable ingress | `false` |
| `global.debug` | Enable debug mode | `false` |

### TimescaleDB Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `timescaledb.enabled` | Enable TimescaleDB deployment | `true` |
| `timescaledb.database.name` | Database name | `jupyterhub_metrics` |
| `timescaledb.database.user` | Database username | `metrics_user` |
| `timescaledb.database.password` | Database password (required) | `""` |
| `timescaledb.database.port` | Database port | `5432` |
| `timescaledb.external.enabled` | Use external database instead of deploying TimescaleDB | `false` |
| `timescaledb.external.host` | External database hostname | `""` |
| `timescaledb.external.port` | External database port | `5432` |
| `timescaledb.image.repository` | TimescaleDB image repository | `timescale/timescaledb` |
| `timescaledb.image.tag` | TimescaleDB image tag | `latest-pg15` |
| `timescaledb.image.pullPolicy` | TimescaleDB image pull policy | `IfNotPresent` |
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
| `timescaledb.podSecurityContext.fsGroup` | Pod fsGroup | `999` |
| `timescaledb.podSecurityContext.runAsNonRoot` | Run as non-root user | `true` |
| `timescaledb.podSecurityContext.runAsUser` | User ID to run as | `999` |
| `timescaledb.containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |
| `timescaledb.containerSecurityContext.capabilities.drop` | Dropped capabilities | `["ALL"]` |
| `timescaledb.containerSecurityContext.seccompProfile.type` | Seccomp profile type | `RuntimeDefault` |

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
| `grafana.persistence.enabled` | Enable persistent volume for Grafana | `true` |
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
| `grafana.podSecurityContext.fsGroup` | Pod fsGroup | `472` |
| `grafana.podSecurityContext.runAsNonRoot` | Run as non-root user | `true` |
| `grafana.podSecurityContext.runAsUser` | User ID to run as | `472` |
| `grafana.containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |
| `grafana.containerSecurityContext.capabilities.drop` | Dropped capabilities | `["ALL"]` |
| `grafana.containerSecurityContext.seccompProfile.type` | Seccomp profile type | `RuntimeDefault` |

### Metrics Collector

| Parameter | Description | Default |
|-----------|-------------|---------|
| `collector.enabled` | Enable metrics collector | `true` |
| `collector.interval` | Collection interval in seconds | `300` |
| `collector.image.repository` | Collector Docker image repository | `ncsa/jupyterhub-metrics-collector` |
| `collector.image.pullPolicy` | Collector image pull policy | `IfNotPresent` |
| `collector.resources.requests.memory` | Memory request | `128Mi` |
| `collector.resources.requests.cpu` | CPU request | `100m` |
| `collector.resources.limits.memory` | Memory limit | `512Mi` |
| `collector.resources.limits.cpu` | CPU limit | `500m` |
| `collector.podSecurityContext.runAsNonRoot` | Run as non-root user | `true` |
| `collector.podSecurityContext.runAsUser` | User ID to run as | `65534` |
| `collector.containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |
| `collector.containerSecurityContext.capabilities.drop` | Dropped capabilities | `["ALL"]` |
| `collector.containerSecurityContext.seccompProfile.type` | Seccomp profile type | `RuntimeDefault` |

**Note:** The collector image version is automatically set to match the chart version (from Chart.yaml). The collector image must be built and pushed before deploying the chart.

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
| `security.networkPolicyEnabled` | Enable NetworkPolicy for traffic restriction | `false` |
| `security.podSecurityPolicyEnabled` | Enable Pod Security Policy (legacy) | `false` |

### Advanced Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `advanced.nodeSelector` | Node selector for pod placement | `{}` |
| `advanced.tolerations` | Pod tolerations | `[]` |
| `advanced.affinity` | Pod affinity rules | `{}` |
| `advanced.priorityClassName` | Priority class name | `""` |
| `advanced.kubeWaitTimeout` | Resource creation timeout (seconds) | `300` |

### Source Files Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `sourceFiles.initDbSql` | Path to init-db.sql (relative to project root) | `init-db.sql` |
| `sourceFiles.collectorScript` | Path to collector.sh (relative to project root) | `collector.sh` |
| `sourceFiles.grafanaProvisioning` | Path to Grafana provisioning directory | `grafana/provisioning` |
| `sourceFiles.grafanaDashboards` | Path to Grafana dashboards directory | `grafana/dashboards` |

**Note:** These paths are used by the `update-chart.sh` script to sync source files into the Helm chart templates. They are not used at runtime.

## Examples

### Basic Installation with Required Parameters

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.database.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password"
```

### Installation with External Database

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.enabled=false \
  --set timescaledb.external.enabled=true \
  --set timescaledb.external.host="postgresql.example.com" \
  --set timescaledb.external.port="5432" \
  --set timescaledb.database.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password"
```

### Installation with Ingress and TLS

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.database.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password" \
  --set ingress.enabled=true \
  --set ingress.host="metrics.example.com" \
  --set ingress.tls.enabled=true \
  --set ingress.tls.certManagerIssuer="letsencrypt-prod"
```

### Installation with Custom Grafana Storage

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.database.password="my-secure-db-password" \
  --set grafana.adminPassword="my-secure-grafana-password" \
  --set grafana.persistence.size="10Gi"
```

### Installation with External Secrets

When using an external secrets management solution (e.g., External Secrets Operator with AWS Secrets Manager, HashiCorp Vault, etc.), you can reference an existing Kubernetes Secret instead of having Helm create one.

**Important:** When `secrets.externalSecretEnabled: true`, the chart will NOT create a Secret resource. You must ensure your external secret exists before installation.

#### Prerequisites

1. Install External Secrets Operator (or your secret management solution)
2. Create an ExternalSecret that syncs to a Kubernetes Secret with these required keys:
   - `POSTGRES_DB` - Database name
   - `POSTGRES_USER` - Database username
   - `POSTGRES_PASSWORD` - Database password
   - `GF_SECURITY_ADMIN_USER` - Grafana admin username
   - `GF_SECURITY_ADMIN_PASSWORD` - Grafana admin password

#### Example: Using External Secrets Operator with AWS Secrets Manager

```bash
# Step 1: Create ExternalSecret resource
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: jupyterhub-metrics-secrets
  namespace: jupyterhub-metrics
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: jupyterhub-metrics-secrets
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_DB
      remoteRef:
        key: jupyterhub-metrics/database
        property: database_name
    - secretKey: POSTGRES_USER
      remoteRef:
        key: jupyterhub-metrics/database
        property: database_user
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: jupyterhub-metrics/database
        property: database_password
    - secretKey: GF_SECURITY_ADMIN_USER
      remoteRef:
        key: jupyterhub-metrics/grafana
        property: admin_user
    - secretKey: GF_SECURITY_ADMIN_PASSWORD
      remoteRef:
        key: jupyterhub-metrics/grafana
        property: admin_password
EOF

# Step 2: Install the chart referencing the external secret
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set secrets.externalSecretEnabled=true \
  --set secrets.externalSecretName="jupyterhub-metrics-secrets"
```

#### Example: Using a Pre-existing Kubernetes Secret

If you have a Kubernetes Secret already created (not managed by External Secrets Operator):

```bash
# Step 1: Create the secret manually
kubectl create secret generic my-jupyterhub-secrets \
  --namespace jupyterhub-metrics \
  --from-literal=POSTGRES_DB=jupyterhub_metrics \
  --from-literal=POSTGRES_USER=metrics_user \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=GF_SECURITY_ADMIN_USER=admin \
  --from-literal=GF_SECURITY_ADMIN_PASSWORD="$(openssl rand -base64 32)"

# Step 2: Install the chart referencing the external secret
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set secrets.externalSecretEnabled=true \
  --set secrets.externalSecretName="my-jupyterhub-secrets"
```

#### Using Custom Secret Key Names

If your external secret uses different key names for passwords:

```bash
helm install my-release ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set secrets.externalSecretEnabled=true \
  --set secrets.externalSecretName="my-jupyterhub-secrets" \
  --set secrets.externalSecretDbPasswordKey="db-password" \
  --set secrets.externalSecretGrafanaPasswordKey="grafana-admin-password"
```

**Note:** When using custom key names, your secret must still contain `POSTGRES_DB`, `POSTGRES_USER`, `GF_SECURITY_ADMIN_USER` with those exact names. Only the password keys can be customized.

### Installation Using Values File

```bash
# Create values-prod.yaml
cat > values-prod.yaml << EOF
timescaledb:
  database:
    password: "my-secure-database-password"
  storage:
    size: 100Gi
    storageClass: fast-ssd
grafana:
  adminPassword: "my-secure-grafana-password"
  replicas: 2
  persistence:
    size: 10Gi
ingress:
  enabled: true
  host: metrics.example.com
  tls:
    enabled: true
    certManagerIssuer: letsencrypt-prod
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
  --set timescaledb.database.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)" \
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

To upgrade with a specific chart version (ensure the collector image for that version exists):

```bash
helm upgrade my-release ./chart \
  --namespace jupyterhub-metrics \
  --version 1.0.0 \
  -f values.yaml
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

When you update the source files in the project root (init-db.sql, collector/, Grafana dashboards), synchronize them into the chart and build the collector image:

```bash
./update-chart.sh
```

This script will:

- Build the collector Docker image with the current Chart version
- Push the image to the registry
- Sync source files into the Helm chart templates

Then commit and deploy:

```bash
git add chart/
git commit -m "chore: update helm chart to version X.Y.Z"
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
