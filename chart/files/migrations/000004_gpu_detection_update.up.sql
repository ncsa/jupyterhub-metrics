-- Update GPU node detection in user_session_stats view
-- Switch from CPU-exclusion heuristic (NOT ILIKE '%cpu%') to explicit GPU model
-- matching (v100, a100, h100, h200). Handles H200 nodes added to cluster.

CREATE OR REPLACE VIEW user_session_stats AS
SELECT
  user_email,
  SUM(runtime_hours) AS total_hours,
  SUM(CASE WHEN (node_name ILIKE '%v100%' OR node_name ILIKE '%a100%' OR node_name ILIKE '%h100%' OR node_name ILIKE '%h200%') THEN runtime_hours ELSE 0 END) AS gpu_hours,
  SUM(CASE WHEN NOT (node_name ILIKE '%v100%' OR node_name ILIKE '%a100%' OR node_name ILIKE '%h100%' OR node_name ILIKE '%h200%') THEN runtime_hours ELSE 0 END) AS cpu_hours,
  COUNT(*) AS total_sessions,
  COUNT(DISTINCT container_base) AS applications_used,
  MIN(session_start) AS first_session,
  MAX(session_end) AS last_session
FROM user_sessions
GROUP BY user_email;

COMMENT ON COLUMN user_session_stats.gpu_hours IS 'Total runtime hours on GPU nodes (v100, a100, h100, h200 by node name pattern)';
COMMENT ON COLUMN user_session_stats.cpu_hours IS 'Total runtime hours on CPU-only nodes (not v100, a100, h100, or h200)';
