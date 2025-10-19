-- Create TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- User mapping table
-- Maps email to user_id (extracted from jupyter-{userid} pod names) and full name
CREATE TABLE users (
    email TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    full_name TEXT,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW()
);

-- Create index on user_id for lookups
CREATE INDEX idx_users_user_id ON users (user_id);

-- Add column comments for users table
COMMENT ON TABLE users IS 'User mapping table - maps email addresses to user IDs and full names extracted from JupyterHub pods';
COMMENT ON COLUMN users.email IS 'User email address from GIT_AUTHOR_EMAIL environment variable (primary key)';
COMMENT ON COLUMN users.user_id IS 'User ID extracted from pod name (jupyter-{user_id}-...)';
COMMENT ON COLUMN users.full_name IS 'Full name from GIT_AUTHOR_NAME environment variable';
COMMENT ON COLUMN users.first_seen IS 'Timestamp when user was first observed';
COMMENT ON COLUMN users.last_seen IS 'Timestamp when user was last observed (updated on each data collection)';

-- Raw observations table
CREATE TABLE container_observations (
    timestamp TIMESTAMPTZ NOT NULL,
    user_email TEXT NOT NULL,
    user_name TEXT,
    node_name TEXT NOT NULL,
    container_image TEXT NOT NULL,
    container_base TEXT NOT NULL,
    container_version TEXT,
    age_seconds INTEGER,
    pod_name TEXT,
    PRIMARY KEY (user_email, pod_name, timestamp)
);

-- Convert to hypertable for time-series optimization
SELECT create_hypertable('container_observations', 'timestamp');

-- Add column comments for container_observations table
COMMENT ON TABLE container_observations IS 'Raw time-series observations of running JupyterHub containers collected every 5 minutes';
COMMENT ON COLUMN container_observations.timestamp IS 'Time when this observation was recorded (UTC)';
COMMENT ON COLUMN container_observations.user_email IS 'User email address from GIT_AUTHOR_EMAIL environment variable';
COMMENT ON COLUMN container_observations.user_name IS 'User full name from GIT_AUTHOR_NAME environment variable (cached for convenience)';
COMMENT ON COLUMN container_observations.node_name IS 'Kubernetes node name where the container is running (e.g., cori-prod-worker-a100-01)';
COMMENT ON COLUMN container_observations.container_image IS 'Full container image with tag (e.g., jupyter/datascience-notebook:latest)';
COMMENT ON COLUMN container_observations.container_base IS 'Container image name without tag or registry (e.g., datascience-notebook)';
COMMENT ON COLUMN container_observations.container_version IS 'Container image tag/version (e.g., latest, 2023-11-01)';
COMMENT ON COLUMN container_observations.age_seconds IS 'Container age in seconds since pod creation (use MAX per pod to calculate session runtime)';
COMMENT ON COLUMN container_observations.pod_name IS 'Kubernetes pod name (e.g., jupyter-username-abc123)';

-- Create indexes for common queries
CREATE INDEX idx_user_email ON container_observations (user_email, timestamp DESC);
CREATE INDEX idx_node_name ON container_observations (node_name, timestamp DESC);
CREATE INDEX idx_container_base ON container_observations (container_base, timestamp DESC);
CREATE INDEX idx_timestamp ON container_observations (timestamp DESC);

-- Additional indexes to optimize session view queries
-- These speed up the window functions and partitioning used in user_sessions view
CREATE INDEX idx_sessions_partition ON container_observations (user_email, pod_name, node_name, timestamp DESC);
CREATE INDEX idx_timestamp_range ON container_observations (timestamp DESC) WHERE timestamp IS NOT NULL;
CREATE INDEX idx_user_timestamp ON container_observations (user_email, timestamp DESC, pod_name, node_name);
CREATE INDEX idx_node_timestamp ON container_observations (node_name, timestamp DESC, user_email);
CREATE INDEX idx_container_timestamp ON container_observations (container_base, timestamp DESC, user_email);

-- Enable compression (compress data older than 7 days)
ALTER TABLE container_observations SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_email,node_name,container_base'
);

SELECT add_compression_policy('container_observations', INTERVAL '7 days');

-- Continuous aggregate: Hourly stats per node
CREATE MATERIALIZED VIEW hourly_node_stats
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', timestamp) AS hour,
    node_name,
    COUNT(DISTINCT user_email) AS unique_users,
    COUNT(DISTINCT pod_name) AS total_containers,
    AVG(age_seconds) AS avg_age_seconds
FROM container_observations
GROUP BY hour, node_name
WITH NO DATA;

SELECT add_continuous_aggregate_policy('hourly_node_stats',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- Add column comments for hourly_node_stats
-- Note: TimescaleDB continuous aggregates are created as views, not materialized views
COMMENT ON VIEW hourly_node_stats IS 'Hourly aggregated statistics per Kubernetes node (automatically maintained by TimescaleDB)';
COMMENT ON COLUMN hourly_node_stats.hour IS 'Start of the 1-hour time bucket';
COMMENT ON COLUMN hourly_node_stats.node_name IS 'Kubernetes node name';
COMMENT ON COLUMN hourly_node_stats.unique_users IS 'Number of distinct users with containers on this node during the hour';
COMMENT ON COLUMN hourly_node_stats.total_containers IS 'Number of distinct containers (pods) running on this node during the hour';
COMMENT ON COLUMN hourly_node_stats.avg_age_seconds IS 'Average container age in seconds during the hour';

-- Continuous aggregate: Hourly stats per container image
CREATE MATERIALIZED VIEW hourly_image_stats
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', timestamp) AS hour,
    container_base,
    container_version,
    COUNT(DISTINCT user_email) AS unique_users,
    COUNT(DISTINCT pod_name) AS total_containers
FROM container_observations
GROUP BY hour, container_base, container_version
WITH NO DATA;

SELECT add_continuous_aggregate_policy('hourly_image_stats',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- Add column comments for hourly_image_stats
-- Note: TimescaleDB continuous aggregates are created as views, not materialized views
COMMENT ON VIEW hourly_image_stats IS 'Hourly aggregated statistics per container image (automatically maintained by TimescaleDB)';
COMMENT ON COLUMN hourly_image_stats.hour IS 'Start of the 1-hour time bucket';
COMMENT ON COLUMN hourly_image_stats.container_base IS 'Container image name without tag';
COMMENT ON COLUMN hourly_image_stats.container_version IS 'Container image version/tag';
COMMENT ON COLUMN hourly_image_stats.unique_users IS 'Number of distinct users using this image during the hour';
COMMENT ON COLUMN hourly_image_stats.total_containers IS 'Number of distinct containers using this image during the hour';

-- Data retention policy (optional - keep raw data for 1 year)
SELECT add_retention_policy('container_observations', INTERVAL '365 days');

-- User session views for Grafana dashboards
-- A session is defined as:
--   1. Continuous observations on the same pod AND node
--   2. With no more than 1 hour gap between observations
--   3. If a pod moves to a new node, it starts a new session
--
-- Note: This is a materialized view for performance (regular views are too slow with large datasets)
-- The collector.sh script automatically refreshes this after each data collection

CREATE MATERIALIZED VIEW user_sessions AS
WITH time_gaps AS (
  SELECT
    user_email,
    pod_name,
    node_name,
    timestamp,
    container_base,
    container_version,
    LAG(timestamp) OVER (PARTITION BY user_email, pod_name, node_name ORDER BY timestamp) AS prev_timestamp
  FROM container_observations
),
session_starts AS (
  SELECT
    user_email,
    pod_name,
    node_name,
    timestamp,
    container_base,
    container_version,
    CASE
      WHEN prev_timestamp IS NULL THEN 1
      WHEN timestamp - prev_timestamp > INTERVAL '1 hour' THEN 1
      ELSE 0
    END AS is_new_session
  FROM time_gaps
),
sessions_numbered AS (
  SELECT
    user_email,
    pod_name,
    node_name,
    timestamp,
    container_base,
    container_version,
    SUM(is_new_session) OVER (PARTITION BY user_email, pod_name, node_name ORDER BY timestamp) AS session_id
  FROM session_starts
)
SELECT
  user_email,
  pod_name,
  node_name,
  session_id,
  MIN(timestamp) AS session_start,
  MAX(timestamp) AS session_end,
  EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp))) / 3600.0 AS runtime_hours,
  MODE() WITHIN GROUP (ORDER BY container_base) AS container_base,
  MODE() WITHIN GROUP (ORDER BY container_version) AS container_version
FROM sessions_numbered
GROUP BY user_email, pod_name, node_name, session_id;

-- Create unique index for CONCURRENTLY refresh (required for materialized view)
CREATE UNIQUE INDEX idx_user_sessions_unique
ON user_sessions (user_email, pod_name, node_name, session_id);

-- Create indexes for fast filtering on materialized view
CREATE INDEX idx_user_sessions_user_time ON user_sessions (user_email, session_start DESC, session_end DESC);
CREATE INDEX idx_user_sessions_time_range ON user_sessions (session_start DESC, session_end DESC);
CREATE INDEX idx_user_sessions_node ON user_sessions (node_name, session_start DESC);
CREATE INDEX idx_user_sessions_container ON user_sessions (container_base, session_start DESC);

-- Add column comments for user_sessions materialized view
COMMENT ON COLUMN user_sessions.user_email IS 'User email address';
COMMENT ON COLUMN user_sessions.pod_name IS 'Kubernetes pod name';
COMMENT ON COLUMN user_sessions.node_name IS 'Kubernetes node name (sessions are split if pod moves to different node)';
COMMENT ON COLUMN user_sessions.session_id IS 'Sequential session number for this user/pod/node combination';
COMMENT ON COLUMN user_sessions.session_start IS 'Timestamp when the session started (first observation)';
COMMENT ON COLUMN user_sessions.session_end IS 'Timestamp when the session ended (last observation)';
COMMENT ON COLUMN user_sessions.runtime_hours IS 'Session runtime in hours (session_end - session_start)';
COMMENT ON COLUMN user_sessions.container_base IS 'Container image name without tag (most common value during session)';
COMMENT ON COLUMN user_sessions.container_version IS 'Container image version/tag (most common value during session)';

-- Aggregated session statistics per user (regular view on top of materialized view)
CREATE OR REPLACE VIEW user_session_stats AS
SELECT
  user_email,
  SUM(runtime_hours) AS total_hours,
  SUM(CASE WHEN node_name NOT ILIKE '%cpu%' THEN runtime_hours ELSE 0 END) AS gpu_hours,
  SUM(CASE WHEN node_name ILIKE '%cpu%' THEN runtime_hours ELSE 0 END) AS cpu_hours,
  COUNT(*) AS total_sessions,
  COUNT(DISTINCT container_base) AS applications_used,
  MIN(session_start) AS first_session,
  MAX(session_end) AS last_session
FROM user_sessions
GROUP BY user_email;

-- Add column comments for user_session_stats view
COMMENT ON COLUMN user_session_stats.user_email IS 'User email address';
COMMENT ON COLUMN user_session_stats.total_hours IS 'Total runtime hours across all sessions';
COMMENT ON COLUMN user_session_stats.gpu_hours IS 'Total runtime hours on GPU nodes (node_name NOT ILIKE ''%cpu%'')';
COMMENT ON COLUMN user_session_stats.cpu_hours IS 'Total runtime hours on CPU-only nodes (node_name ILIKE ''%cpu%'')';
COMMENT ON COLUMN user_session_stats.total_sessions IS 'Total number of sessions (continuous runs with < 1 hour gaps)';
COMMENT ON COLUMN user_session_stats.applications_used IS 'Number of distinct container images used';
COMMENT ON COLUMN user_session_stats.first_session IS 'Timestamp of first session start';
COMMENT ON COLUMN user_session_stats.last_session IS 'Timestamp of most recent session end';

COMMENT ON MATERIALIZED VIEW user_sessions IS 'Pre-computed user sessions (materialized view). A session is a continuous run of a pod on a specific node with < 1 hour gaps. Refreshed automatically by collector.sh after each data collection.';
COMMENT ON VIEW user_session_stats IS 'Aggregated session statistics per user (total hours, GPU/CPU breakdown, session count, etc.). Built on top of user_sessions materialized view.';
