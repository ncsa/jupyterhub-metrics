# Dashboard Queries Reference

This document describes the queries used in the Grafana dashboards and how the session data is computed.

## Data Architecture

### Materialized View: `user_sessions`
- Pre-computed session data for fast queries
- Automatically refreshed after each data collection (~5 minutes)
- Query performance: < 100ms (vs 2-3 seconds with regular views)

### Regular View: `user_session_stats`
- Aggregated all-time statistics per user
- Built on top of `user_sessions` materialized view
- Used for quick lookups of total hours, sessions, etc.

## Session Definition

A session is defined as:
- Continuous observations of the same **pod on the same node**
- With **no more than 1 hour gap** between observations
- If a pod moves to a different node, it starts a **new session**

This ensures accurate tracking of GPU vs CPU usage since node changes are treated as separate sessions.

GPU vs CPU classification:
- **GPU hours**: Sessions where `node_name NOT ILIKE '%cpu%'` (e.g., cori-prod-worker-a100-XX)
- **CPU hours**: Sessions where `node_name ILIKE '%cpu%'` (e.g., cori-prod-worker-cpu-XX)

## User Detail Dashboard Queries

All queries filter by time range to show only sessions within the selected dashboard time window.

### Stat Panels (Total Hours, GPU Hours, CPU Hours, Sessions, Applications)
```sql
-- Total Hours
SELECT 
  COALESCE(SUM(runtime_hours), 0) AS "Total Hours"
FROM user_sessions
WHERE user_email = '$user'
  AND session_start >= $__timeFrom()
  AND session_end <= $__timeTo();

-- GPU Hours
SELECT 
  COALESCE(SUM(runtime_hours), 0) AS "GPU Hours"
FROM user_sessions
WHERE user_email = '$user'
  AND node_name NOT ILIKE '%cpu%'
  AND session_start >= $__timeFrom()
  AND session_end <= $__timeTo();

-- CPU Hours
SELECT 
  COALESCE(SUM(runtime_hours), 0) AS "CPU Hours"
FROM user_sessions
WHERE user_email = '$user'
  AND node_name ILIKE '%cpu%'
  AND session_start >= $__timeFrom()
  AND session_end <= $__timeTo();

-- Total Sessions
SELECT 
  COALESCE(COUNT(*), 0) AS "Total Sessions"
FROM user_sessions
WHERE user_email = '$user'
  AND session_start >= $__timeFrom()
  AND session_end <= $__timeTo();

-- Applications Used
SELECT 
  COALESCE(COUNT(DISTINCT container_base), 0) AS "Applications Used"
FROM user_sessions
WHERE user_email = '$user'
  AND session_start >= $__timeFrom()
  AND session_end <= $__timeTo();
```

### User Sessions Table
```sql
SELECT
  session_start AS "Session Start",
  session_end AS "Session End",
  runtime_hours AS "Runtime (Hours)",
  node_name AS "Node",
  container_base || ':' || container_version AS "Container Image"
FROM user_sessions
WHERE user_email = '$user'
  AND session_start >= $__timeFrom()
  AND session_end <= $__timeTo()
ORDER BY session_start DESC;
```

## Overview Dashboard Queries

### Top Users by Runtime (Table)
```sql
SELECT
  us.user_email AS "User Email",
  COALESCE(u.full_name, us.user_email) AS "User Name",
  SUM(us.runtime_hours) AS "Total Runtime (Hours)",
  COUNT(*) AS "Application Sessions",
  MAX(us.session_end) AS "Last Seen"
FROM user_sessions us
LEFT JOIN users u ON us.user_email = u.email
WHERE us.session_start >= $__timeFrom()
  AND us.session_end <= $__timeTo()
GROUP BY us.user_email, u.full_name
ORDER BY "Total Runtime (Hours)" DESC
LIMIT 50;
```

### Application Usage (Table)
```sql
SELECT
  container_base AS "Application",
  string_agg(DISTINCT container_version, ', ' ORDER BY container_version) AS "Version",
  COUNT(DISTINCT user_email) AS "Unique Users",
  COUNT(*) AS "Total Sessions"
FROM user_sessions
WHERE session_start >= $__timeFrom()
  AND session_end <= $__timeTo()
GROUP BY container_base
ORDER BY "Total Sessions" DESC;
```

### Active Users Over Time (Time Series)
```sql
SELECT
  time_bucket('$__interval', timestamp) AS time,
  COUNT(DISTINCT user_email) AS "Active Users"
FROM container_observations
WHERE $__timeFilter(timestamp)
GROUP BY time
ORDER BY time;
```

### Applications per Node Over Time (Time Series)
```sql
SELECT
  time_bucket('$__interval', timestamp) AS time,
  node_name AS metric,
  COUNT(DISTINCT pod_name) AS value
FROM container_observations
WHERE $__timeFilter(timestamp)
GROUP BY time, metric
ORDER BY time;
```

## Performance Characteristics

| Query Type | Data Source | Typical Response Time | Freshness |
|------------|-------------|----------------------|-----------|
| Session queries | `user_sessions` (materialized) | < 100ms | ~5 minutes |
| Time-series | `container_observations` | < 500ms | Real-time |
| Aggregates | `user_session_stats` | < 50ms | ~5 minutes |

## Maintenance

The materialized view is automatically refreshed by `collector.sh` after each data collection:

```bash
# Runs after every data insert (every 5 minutes)
REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions;
```

Manual refresh (if needed):
```bash
psql -h localhost -U metrics_user -d jupyterhub_metrics \
  -c "REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions;"
```

Check materialized view size and row count:
```sql
SELECT 
  pg_size_pretty(pg_total_relation_size('user_sessions')) AS size,
  COUNT(*) AS sessions
FROM user_sessions;
```
