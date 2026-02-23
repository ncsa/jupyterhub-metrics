-- Restore user_session_stats view to the legacy CPU-exclusion heuristic
-- (nodes without "cpu" in their name are treated as GPU nodes)

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

COMMENT ON COLUMN user_session_stats.gpu_hours IS 'Total runtime hours on non-CPU nodes (legacy: nodes without "cpu" in name)';
COMMENT ON COLUMN user_session_stats.cpu_hours IS 'Total runtime hours on CPU-only nodes (legacy: nodes with "cpu" in name)';
