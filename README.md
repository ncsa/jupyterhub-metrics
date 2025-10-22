# JupyterHub Container Metrics System

A complete monitoring solution for tracking JupyterHub container usage with TimescaleDB, Grafana, and automated data collection.

## Features

- **Automated Data Collection**: Collects container metrics every 5 minutes
- **Time-Series Optimization**: Uses TimescaleDB for efficient storage with automatic compression
- **Pre-Aggregated Views**: Continuous aggregates for fast queries on large datasets
- **Interactive Dashboards**: Grafana dashboards with customizable time windows
- **Long-Term Storage**: Optimized for years of data with minimal storage

## Architecture

```
┌─────────────────┐
│  Kubernetes     │
│  (JupyterHub)   │
└────────┬────────┘
         │
         │ kubectl
         │
┌────────▼────────┐      ┌─────────────────┐
│   Collector     │─────▶│  TimescaleDB    │
│   (Docker)      │      │  (PostgreSQL)   │
└─────────────────┘      └────────┬────────┘
                                  │
                         ┌────────▼────────┐
                         │    Grafana      │
                         │  (Port 3000)    │
                         └─────────────────┘
```

## Deployment Options

### Option 1: Kubernetes Deployment with Helm (Recommended)

Deploy the entire system directly in your Kubernetes cluster using the included Helm chart.

**Advantages:**
- No external kubectl configuration needed
- Automatic service discovery
- Native Kubernetes RBAC integration
- Better security with in-cluster authentication
- Secrets managed by Kubernetes (not `.env` files)
- Easy upgrades and rollbacks with Helm

**Configuration in Kubernetes:**
- All sensitive data is stored in Kubernetes Secrets
- Scripts automatically use environment variables injected by Kubernetes
- No `.env` file needed in the container

See **[chart/README.md](chart/README.md)** for detailed Helm chart documentation.

**Quick deploy:**
```bash
# Install with Helm
helm install jupyterhub-metrics ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set db.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)"
```

For more details, see [HELM_CHART.md](HELM_CHART.md).

**Building and Updating the Chart:**

The `update-chart.sh` script performs all necessary updates including multi-architecture builds:

```bash
# Update chart files, build multi-arch collector image, and bump version
./update-chart.sh

# Build only, don't push to registry
PUSH_TO_REGISTRY=false ./update-chart.sh

# Then deploy with Helm
helm install jupyterhub-metrics ./chart \
  --namespace jupyterhub-metrics \
  --create-namespace \
  --set timescaledb.database.password="$(openssl rand -base64 32)" \
  --set grafana.adminPassword="$(openssl rand -base64 32)"
```

The `update-chart.sh` script:
- Syncs source files (init-db.sql, Grafana configs) to chart/files/
- Builds multi-architecture Docker images from `collector/Dockerfile`
  - **linux/amd64** (x86 - Intel/AMD)
  - **linux/arm64** (ARM - Raspberry Pi, Apple Silicon, etc.)
- **Collector image version automatically matches Chart version**
- Pushes to `ncsa/jupyterhub-metrics-collector:<chart-version>`
- Automatically bumps the patch version in Chart.yaml if anything changed
- Deployment template uses `.Chart.Version` directly for image tag
- Requires Docker with buildx support (install via [Docker Build documentation](https://docs.docker.com/build/))
- Falls back to single-arch build if buildx not available

**Typical workflow:**
```bash
# 1. Make changes to collector.sh, init-db.sql, or grafana configs
# 2. Run update script (bumps chart version automatically)
./update-chart.sh
# This will:
#   - Sync files to chart/
#   - Build collector image with current version (e.g., 1.0.1)
#   - Bump Chart.yaml from 1.0.0 to 1.0.1
#   - Push ncsa/jupyterhub-metrics-collector:1.0.1
#   - Deployment template uses .Chart.Version → ncsa/jupyterhub-metrics-collector:1.0.1

# 3. Review and commit changes
git add chart/ && git commit -m "chore: update helm chart to vX.Y.Z"
git tag vX.Y.Z

# 4. Deploy the updated chart
helm install jupyterhub-metrics ./chart
# Image version is automatically set from .Chart.Version (from Chart.yaml)
```

### Option 2: Docker Compose (Local Development)

Run TimescaleDB and Grafana in Docker, with the collector using your local kubectl configuration.

**Advantages:**
- Easier local development and testing
- Can monitor multiple clusters
- No cluster permissions needed for database/Grafana

See instructions below for Docker Compose setup.

---

## Quick Start (Docker Compose)

### Prerequisites

- Docker and Docker Compose
- kubectl configured with access to your Kubernetes cluster
- Access to JupyterHub namespace in the `cori-prod` context

### Installation

1. **Create directory structure:**

```bash
mkdir -p jupyterhub-metrics/{grafana/{provisioning/{datasources,dashboards},dashboards}}
cd jupyterhub-metrics
```

2. **Create all configuration files:**

Save the following files in your directory:
- `docker-compose.yml`
- `collector/Dockerfile` (in collector subfolder)
- `collector/collector.sh` (in collector subfolder)
- `config-loader.sh`
- `init-db.sql`
- `grafana/provisioning/datasources/timescaledb.yml`
- `grafana/provisioning/dashboards/dashboards.yml`
- `grafana/dashboards/jupyterhub-overview.json`

3. **Set up centralized configuration:**

```bash
# Copy configuration template
cp .env.example .env

# Edit .env with your actual values
nano .env
```

Update the following in `.env`:
- `DB_PASSWORD`: Secure database password
- `GRAFANA_ADMIN_PASSWORD`: Secure Grafana password
- `DB_HOST`: Database hostname (default: `localhost` for Docker Compose)
- `KUBECTL_CONTEXT`: Your Kubernetes context (default: `cori-prod`)
- `NAMESPACE`: Your JupyterHub namespace (default: `jupyterhub`)

See [SECURITY.md](SECURITY.md) for detailed configuration instructions.

4. **Start the services:**

```bash
docker-compose up -d
```

5. **Verify services are running:**

```bash
docker-compose ps
docker-compose logs -f
```

6. **Access Grafana:**

Open your browser to `http://localhost:3000`
- Username: (value from `GRAFANA_ADMIN_USER` in `.env`)
- Password: (value from `GRAFANA_ADMIN_PASSWORD` in `.env`)

## Configuration

All configuration is managed through a centralized `.env` file. This approach keeps sensitive information secure and makes it easy to maintain different configurations for different environments.

### Configuration Management

**This project uses centralized environment configuration. See [SECURITY.md](SECURITY.md) for complete details.**

Quick overview:

1. **Create `.env` from template:**
   ```bash
   cp .env.example .env
   nano .env  # Edit with your values
   ```

2. **Key configuration variables:**
   - `DB_HOST`: Database hostname (default: `localhost`)
   - `DB_PORT`: Database port (default: `5432`)
   - `DB_NAME`: Database name (default: `jupyterhub_metrics`)
   - `DB_USER`: Database user (default: `metrics_user`)
   - `DB_PASSWORD`: Database password (change this!)
   - `GRAFANA_ADMIN_USER`: Grafana username (default: `admin`)
   - `GRAFANA_ADMIN_PASSWORD`: Grafana password (change this!)
   - `GRAFANA_PORT`: Grafana port (default: `3000`)
   - `KUBECTL_CONTEXT`: Kubernetes context (default: `cori-prod`)
   - `NAMESPACE`: Kubernetes namespace (default: `jupyterhub`)
   - `COLLECTION_INTERVAL`: Collection interval in seconds (default: `300`)

3. **Important security notes:**
   - **Never commit `.env` to git** - it's in `.gitignore`
   - **Commit `.env.example` instead** - it contains no real secrets
   - Set secure passwords: `openssl rand -base64 32`
   - Keep `.env` file permissions restrictive: `chmod 600 .env`

### How Configuration Works

- **Shell scripts** (`collector.sh`, `dump-database.sh`, etc.):
  - **Docker Compose**: Source `config-loader.sh` which loads and validates `.env`
  - **Kubernetes**: Use environment variables injected via Secrets/ConfigMaps (no `.env` file needed)
- **Docker Compose** uses Docker's built-in `.env` support for variable substitution
- **Python scripts** load environment variables directly
- **Grafana** reads database credentials from environment variables
- **Kubernetes** uses Secrets and ConfigMaps to inject configuration

### Changing Collection Interval

Edit `.env` and update:

```bash
COLLECTION_INTERVAL=600  # 10 minutes instead of 5
```

Then restart services:

```bash
docker-compose restart collector
```

### Using Different Kubernetes Context

Edit `.env` and update:

```bash
KUBECTL_CONTEXT=your-context-name
```

Then restart the collector:

```bash
docker-compose restart collector
```

## Data Schema

### Main Table: `container_observations`

| Column | Type | Description |
|--------|------|-------------|
| timestamp | TIMESTAMPTZ | When the observation was recorded |
| user_email | TEXT | User's email address |
| user_name | TEXT | User's display name |
| node_name | TEXT | Kubernetes node hosting the container |
| container_image | TEXT | Full container image with tag |
| container_base | TEXT | Container image without version |
| container_version | TEXT | Container image version/tag |
| age_seconds | INTEGER | Container age in seconds |
| pod_name | TEXT | Kubernetes pod name |

### How Runtime Calculation Works

**Important:** Each observation records the container's age since it started. To calculate total runtime correctly:

1. **For a single container session**: Take the MAX(age_seconds) for that pod_name
   - Example: Pod runs for 2 hours, sampled every 5 min → MAX gives you 7200 seconds (2 hours)
   
2. **For multiple sessions**: Sum the MAX age of each unique pod_name
   - Session 1: Pod `jupyter-user1-abc123` runs 2 hours → 7200 seconds
   - Session 2: Pod `jupyter-user1-xyz789` runs 3 hours → 10800 seconds
   - **Total runtime: 5 hours** (not the sum of all observations!)

3. **Why this matters**: 
   - ❌ Wrong: `SUM(age_seconds)` counts every observation → massive over-counting
   - ✅ Correct: `SUM(MAX(age_seconds) per pod)` counts each session once

**Example scenario:**
- User starts container at 10:00 AM
- We sample at: 10:05 (age=300s), 10:10 (age=600s), 10:15 (age=900s)
- User stops container at 10:15 AM
- ❌ Wrong calculation: 300 + 600 + 900 = 1800 seconds (30 min)
- ✅ Correct calculation: MAX(300, 600, 900) = 900 seconds (15 min)

### Database Schema

**Tables:**
- `users`: User mapping table (email, user_id, full_name)
- `container_observations`: Raw time-series observations (TimescaleDB hypertable)

**Views:**
- `user_sessions`: Pre-computed user sessions (materialized view, refreshed automatically)
- `user_session_stats`: Aggregated session statistics per user
- `hourly_node_stats`: Containers per node aggregated hourly (TimescaleDB continuous aggregate)
- `hourly_image_stats`: Container image usage aggregated hourly (TimescaleDB continuous aggregate)

## Using Grafana

### Default Dashboard

The system includes a comprehensive dashboard showing:

1. **Summary Stats**: Active users, containers, nodes, and image types
2. **Time Series Graphs**:
   - Active users over time
   - Total containers over time
   - Containers per node (stacked)
   - Container image usage (stacked)
3. **Tables**:
   - Top users by runtime
   - Container image statistics

### Customizing Time Windows

Use the time picker in the top-right corner:
- **Quick ranges**: Last 5m, 15m, 1h, 6h, 12h, 24h, 7d, 30d, 90d
- **Custom ranges**: Select specific start and end dates
- **Refresh rate**: Auto-refresh every 30s (configurable)

### Creating Custom Queries

Navigate to Explore → Select "TimescaleDB" datasource

**Example: Find users with long-running containers (> 24 hours)**

```sql
-- Get the latest observation for each container
WITH current_containers AS (
  SELECT DISTINCT ON (user_email, pod_name)
    user_email,
    user_name,
    node_name,
    age_seconds / 3600.0 AS age_hours,
    container_base
  FROM container_observations
  ORDER BY user_email, pod_name, timestamp DESC
)
SELECT *
FROM current_containers
WHERE age_hours > 24
ORDER BY age_hours DESC;
```

**Example: Daily active user count**

```sql
SELECT
  time_bucket('1 day', timestamp) AS day,
  COUNT(DISTINCT user_email) AS unique_users
FROM container_observations
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY day
ORDER BY day;
```

**Example: Node utilization heatmap**

```sql
SELECT
  time_bucket('1 hour', timestamp) AS hour,
  node_name,
  COUNT(DISTINCT pod_name) AS container_count
FROM container_observations
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY hour, node_name
ORDER BY hour, node_name;
```

## Useful SQL Queries

### Total runtime by user (current period)

```sql
-- Properly calculates runtime by taking MAX age per pod (session)
-- This avoids double-counting when summing observations
SELECT
  user_email,
  user_name,
  SUM(max_age) / 3600.0 AS total_runtime_hours,
  COUNT(DISTINCT pod_name) AS container_count,
  MAX(last_seen) AS last_seen
FROM (
  SELECT
    user_email,
    user_name,
    pod_name,
    MAX(age_seconds) AS max_age,
    MAX(timestamp) AS last_seen
  FROM container_observations
  WHERE timestamp >= NOW() - INTERVAL '30 days'
  GROUP BY user_email, user_name, pod_name
) AS pod_sessions
GROUP BY user_email, user_name
ORDER BY total_runtime_hours DESC
LIMIT 100;
```

### Peak usage times

```sql
SELECT
  EXTRACT(HOUR FROM timestamp) AS hour_of_day,
  EXTRACT(DOW FROM timestamp) AS day_of_week,
  COUNT(DISTINCT pod_name) AS avg_containers
FROM container_observations
WHERE timestamp >= NOW() - INTERVAL '30 days'
GROUP BY hour_of_day, day_of_week
ORDER BY avg_containers DESC;
```

### Container image adoption over time

```sql
SELECT
  time_bucket('1 week', timestamp) AS week,
  container_base,
  COUNT(DISTINCT user_email) AS unique_users
FROM container_observations
WHERE timestamp >= NOW() - INTERVAL '180 days'
GROUP BY week, container_base
ORDER BY week, unique_users DESC;
```

## Maintenance

### Backup Database

Using the provided backup script (recommended):
```bash
./dump-database.sh
# Creates backup in ./backups/ directory
```

Manual backup:
```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb pg_dump -U $DB_USER $DB_NAME > backup_$(date +%Y%m%d).sql
```

### Restore Database

Using the provided restore script (recommended):
```bash
./restore-database.sh ./backups/jupyterhub_metrics_20240101_120000.sql
```

Manual restore:
```bash
source ./config-loader.sh
cat backup_20240101.sql | docker exec -i jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME
```

### View Database Size

```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME -c "
SELECT
  pg_size_pretty(pg_total_relation_size('container_observations')) AS total_size,
  pg_size_pretty(pg_relation_size('container_observations')) AS table_size,
  pg_size_pretty(pg_total_relation_size('container_observations') - pg_relation_size('container_observations')) AS index_size;
"
```

### Check Compression Status

```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME -c "
SELECT
  chunk_schema || '.' || chunk_name AS chunk,
  pg_size_pretty(before_compression_total_bytes) AS before,
  pg_size_pretty(after_compression_total_bytes) AS after,
  ROUND((1 - after_compression_total_bytes::numeric / before_compression_total_bytes::numeric) * 100, 2) AS compression_ratio
FROM timescaledb_information.compression_settings
WHERE compression_status = 'Compressed'
ORDER BY before_compression_total_bytes DESC
LIMIT 10;
"
```

### Manual Compression

```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME -c "
SELECT compress_chunk(i, if_not_compressed => true)
FROM show_chunks('container_observations', older_than => INTERVAL '7 days') i;
"
```

## Troubleshooting

### Configuration Issues

**Error: "Configuration file not found"**

```
ERROR: Configuration file not found: /path/to/.env
```

Solution: Create `.env` from the template:
```bash
cp .env.example .env
nano .env  # Edit with your values
```

**Error: "Required configuration variables not set"**

```
ERROR: The following required configuration variables are not set:
  - DB_PASSWORD
  - GRAFANA_ADMIN_PASSWORD
```

Solution: Check your `.env` file and ensure all required variables have values (not empty).

**Error: "Port must be a number"**

```
ERROR: DB_PORT must be a number, got: invalid_value
```

Solution: Check `.env` and ensure port numbers are numeric (e.g., `5432` not `"5432"`).

**Docker Compose not picking up `.env` values**

Solution:
1. Verify `.env` file exists in the same directory as `docker-compose.yml`
2. Run `docker-compose config` to see substituted variables
3. Ensure variable names match between `.env` and `docker-compose.yml`
4. Restart services: `docker-compose up -d`

For more configuration help, see [SECURITY.md](SECURITY.md).

### Collector not collecting data

Check logs:
```bash
docker-compose logs collector
```

Common issues:
- kubectl authentication problems
- Wrong Kubernetes context
- Network connectivity to cluster
- Missing `.env` file (check: `docker-compose logs collector`)

Test kubectl manually:
```bash
docker-compose exec collector kubectl --context $(grep KUBECTL_CONTEXT .env | cut -d= -f2) get pods -n $(grep NAMESPACE .env | cut -d= -f2)
```

### Database connection errors

Check if TimescaleDB is running:
```bash
docker-compose ps timescaledb
```

Test database connection using variables from `.env`:
```bash
# Load configuration and test
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -h localhost -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM container_observations;"
```

Verify `.env` values are correct:
```bash
source ./config-loader.sh && echo "DB: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
```

### Grafana not showing data

1. Check datasource connection: Configuration → Data Sources → TimescaleDB → Test
2. Verify data exists: Explore → Run a simple query
3. Check dashboard time range matches your data

### High disk usage

Check if compression is enabled:
```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME -c "
SELECT * FROM timescaledb_information.compression_settings;
"
```

Adjust retention policy if needed (example: keep only 180 days):
```sql
SELECT remove_retention_policy('container_observations');
SELECT add_retention_policy('container_observations', INTERVAL '180 days');
```

## Performance Tuning

### For Large Deployments (10k+ concurrent users)

1. **Increase collection interval** to reduce data points:
   ```yaml
   COLLECTION_INTERVAL: 600  # 10 minutes
   ```

2. **Adjust compression policy** to compress sooner:
   ```sql
   SELECT remove_compression_policy('container_observations');
   SELECT add_compression_policy('container_observations', INTERVAL '1 day');
   ```

3. **Add more indexes** for specific queries if needed

4. **Increase PostgreSQL resources** in docker-compose.yml:
   ```yaml
   timescaledb:
     deploy:
       resources:
         limits:
           memory: 4G
   ```

## Exporting Data

### Export to CSV

```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME -c "
COPY (
  SELECT * FROM container_observations
  WHERE timestamp >= '2024-01-01'
) TO STDOUT WITH CSV HEADER
" > export.csv
```

### Export specific metrics

```bash
source ./config-loader.sh
docker exec jupyterhub-timescaledb psql -U $DB_USER -d $DB_NAME -c "
COPY (
  SELECT
    time_bucket('1 hour', timestamp) AS hour,
    COUNT(DISTINCT user_email) AS active_users,
    COUNT(DISTINCT pod_name) AS total_containers
  FROM container_observations
  WHERE timestamp >= NOW() - INTERVAL '30 days'
  GROUP BY hour
  ORDER BY hour
) TO STDOUT WITH CSV HEADER
" > metrics_summary.csv
```

## Stopping and Cleanup

### Stop services

```bash
docker-compose down
```

### Stop and remove all data

```bash
docker-compose down -v
```

## License

This project is provided as-is for monitoring JupyterHub deployments.
