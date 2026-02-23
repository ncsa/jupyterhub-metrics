-- Tear down all schema objects in reverse dependency order

-- Drop views first (depend on materialized views)
DROP VIEW IF EXISTS user_session_stats;

-- Drop materialized view that depends on hypertable
DROP MATERIALIZED VIEW IF EXISTS user_sessions;

-- Drop continuous aggregate views that depend on hypertable
DROP MATERIALIZED VIEW IF EXISTS hourly_image_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS hourly_node_stats CASCADE;

-- Drop tables (hypertable and regular)
DROP TABLE IF EXISTS container_observations CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Drop extension last (removes all TimescaleDB objects)
DROP EXTENSION IF EXISTS timescaledb CASCADE;
