# Changelog

All notable changes to this Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-02-23

### Added

- New **Node Breakdown** dashboard (`jupyterhub-node-breakdown.json`) with:
  - Cluster summary stat row: total active users, GPU users, CPU users, active sessions,
    GPU nodes occupied, CPU nodes occupied — all showing current live state
  - Per-node active users time-series chart: one line per node showing active users over time
  - Active users on CPU nodes over time (hourly line chart)
  - Active users on GPU nodes over time, broken down by GPU model (H200/H100/A100/V100)
  - GPU hours by model over time (hourly, separate line per GPU generation)
  - CPU hours over time (hourly line chart)
  - Node summary table for the selected time range: node, type, users, sessions, hours —
    sorted by total hours consumed
- Application Details dashboard with application selector dropdown
- Active sessions time series chart to Application Details dashboard
- CPU vs GPU usage pie chart to Application Details dashboard
- Users table with GPU/CPU/Total hours breakdown to Application Details dashboard
- Colleges and departments usage tables to Application Details dashboard
- Summary statistics (Total Hours, Total Users, Total Sessions, Avg Session Duration)
  to Application Details dashboard
- **golang-migrate integration** — database migrations are now tracked with a `schema_migrations`
  table. The `migrate/migrate` Docker image applies pending migrations automatically on
  `helm install` and `helm upgrade`.
- Migrations ConfigMap containing all numbered migration files mounted at `/migrations` in the
  Job pod:
  - `000001_initial_schema` — full schema for fresh installs (tables, indexes, views, policies)
  - `000002_add_college_column` — adds `college` column to `users` table
  - `000003_fix_fellowships_department` — corrects Fellowships department/job_title data
  - `000004_gpu_detection_update` — updates `user_session_stats` view to explicit GPU model matching
- Each migration has a corresponding `.down.sql` file for rollback support.

### Changed

- Updated GPU node classification across all dashboards and the `user_session_stats` database view
  to use explicit GPU model name patterns (`v100`, `a100`, `h100`, `h200`) instead of the previous
  CPU-exclusion heuristic (`NOT ILIKE '%cpu%'`)
- Added H200 GPU node support — nodes matching `%h200%` in their name are now classified as GPU nodes
- Switched remaining `LIKE` clauses to `ILIKE` for case-insensitive matching consistency
- Database init hook now runs on **`post-install` and `post-upgrade`** (previously `post-install`
  only). Safe to run repeatedly — golang-migrate tracks applied versions and skips already-run
  migrations.
- Replaced the `postgres:15-alpine` init container (which ran `psql < init-db.sql`) with the
  `migrate/migrate` image running `migrate up`.
- Migrations ConfigMap is now regenerated on each install/upgrade (`before-hook-creation,hook-succeeded`
  delete policy) to pick up new migrations added in future chart versions.
- Changed Active Users per Node panel from a static table to a time-series line chart (one line
  per node) showing users per node over the selected time range

### Fixed

- Fixed all panels in Application Details dashboard (GPU Hours, CPU Hours, Total Hours, Total Users,
  Total Sessions, Avg Session Duration, Colleges, Departments) — were using
  `session_start >= $__timeFrom() AND session_end <= $__timeTo()` which only counts sessions that
  both started AND ended within the window, missing long-running sessions. Now uses correct overlap
  condition: `session_start <= $__timeTo() AND session_end >= $__timeFrom()`.
- Fixed Application Hours on Node and Sessions on Node panels in Node Detail dashboard — same overlap fix.
- Fixed "Users in Past 24 Hours" in Node Detail dashboard — now uses `container_observations`
  so users with sessions that started before the 24h window are included.
- Fixed "Active" label in Sessions on Node table — `session_end > NOW()` was always false;
  now uses `session_end >= NOW() - INTERVAL '10 minutes'`.
- Fixed "Active Users Now", "Active GPU/CPU Users Now", "Active Sessions Now", "GPU/CPU Nodes Active"
  stat panels in Node Breakdown dashboard — originally queried `user_sessions WHERE session_end > NOW()`
  (always 0), then switched to `container_observations WHERE timestamp >= NOW() - 10 minutes` (still 0
  if the most recent collection is just outside the window). Now uses a `time_bucket('5 minutes')`
  time-series query over the dashboard time range with `lastNotNull` reducer, so the stat always
  reflects the most recent collector run rather than a hard-coded recency window.
- Fixed "Active Users Over Time" and "GPU Hours Over Time" time-series panels in Node Breakdown
  dashboard — were querying `user_sessions WHERE session_start >= $__timeFrom()` which excludes
  long-running sessions that started before the selected time window (the majority of users). Now
  uses `container_observations` with `timestamp BETWEEN $__timeFrom() AND $__timeTo()` which
  correctly counts any user active in each time bucket.
- Fixed "Active Users Over Time" panel in Overview dashboard — same `user_sessions session_start`
  bug; now uses `container_observations` so long-running sessions are counted correctly.
- Fixed same "Users Now", "Applications Now", and "Users Over Time" bugs in Node Detail dashboard.
- Node Summary table now also uses `container_observations` for consistent, accurate hours.
- Made `ingress.annotations`, `ingress.className`, `ingress.host`, and `ingress.tls`
  optional in `values.schema.json`
- Made `grafana.port` optional with default value of 3000
- Made `grafana.anonymous.orgName` and `orgRole` optional when anonymous access is disabled
- Made `collector.interval` optional with default value of 300 seconds

### Existing Deployments — One-Time Stamping Required

Databases already running the current schema must be stamped so golang-migrate knows which
migrations have already been applied. Run **once** after upgrading to this version:

```bash
docker run --rm \
  -v ./chart/files/migrations:/migrations \
  migrate/migrate \
  -path=/migrations \
  -database "postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=disable" \
  force 3
```

For Kubernetes deployments (replace namespace, user, password, host, and database name):

```bash
kubectl -n NAMESPACE run psql-stamp --rm -it --image=postgres:15 \
  --restart=Never -- \
  psql "postgres://USER:PASS@HOST:5432/DBNAME?sslmode=disable" \
  -c "CREATE TABLE IF NOT EXISTS schema_migrations (version bigint NOT NULL, dirty boolean NOT NULL); DELETE FROM schema_migrations; INSERT INTO schema_migrations (version, dirty) VALUES (3, false);"
```

After stamping, future `helm upgrade` calls will apply only new migrations.

### Verification

```bash
# Check current migration version
docker run --rm -v ./chart/files/migrations:/migrations migrate/migrate \
  -path=/migrations \
  -database "postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=disable" \
  version
# Expected output: 4

# Adding a new migration: create 000005_description.up.sql + .down.sql in
# chart/files/migrations/, then docker-compose up or helm upgrade applies it automatically.
```
