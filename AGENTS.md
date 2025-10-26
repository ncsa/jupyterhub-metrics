# AGENTS.md - Guidelines for AI Agents Working on JupyterHub Metrics

This document contains important rules, conventions, and structural information for AI agents (like Claude) working on this codebase. These guidelines help ensure consistency, safety, and efficiency when making changes.

---

## 🚨 Critical Safety Rules

### Database Safety
1. **NEVER DROP TABLES** - Especially when upgrading or modifying schemas
   - Always use `ALTER TABLE` to modify existing tables
   - Use `IF NOT EXISTS` when creating new tables or columns
   - Preserve all existing data during schema changes
   - Example: Use `ALTER TABLE users ADD COLUMN IF NOT EXISTS department TEXT;` instead of dropping and recreating

2. **NEVER DELETE DATA** - Unless explicitly requested by the user
   - Retention policies are **DISABLED** by default - keep all data indefinitely
   - Any deletion scripts must be clearly marked and require explicit confirmation
   - When modifying data, use UPDATE instead of DELETE/INSERT where possible

3. **Always Use Transactions for Data Modifications**
   - Wrap multi-step database changes in transactions
   - Test queries on a small dataset before running on full table
   - Provide rollback instructions for any major changes

---

## 📁 Project Structure

### Root Directory
```
jupyterhub-metrics/
├── .env                          # Database credentials and configuration (DO NOT COMMIT)
├── .env.example                  # Template for environment variables
├── init-db.sql                   # Main database schema definition
├── add-policies.sql              # TimescaleDB policies (compression, aggregates)
├── migrate_*.sql                 # Database migration scripts (dated/versioned)
├── fix_*.sql                     # One-off data fix scripts
├── remove_retention_policy.sql   # Script to disable data retention
├── AGENTS.md                     # This file - guidelines for AI agents
└── README.md                     # Project documentation
```

### Python Scripts
```
├── export_user_details.py              # Fetch user details from MS Graph (device auth)
├── export_user_details_with_token.py   # Fetch user details from MS Graph (token auth)
├── export_user_usage_stats.py          # Export user usage statistics to CSV
├── test_*.py                            # Test scripts (don't modify production data)
```

### Collector
```
collector/
├── collector.sh                  # Main data collection script (runs every 5 minutes)
└── Dockerfile                    # Container for running collector
```

### Helm Chart
```
chart/
├── Chart.yaml                    # Helm chart metadata
├── values.yaml                   # Default configuration values
├── cori-dev.yaml                 # Environment-specific overrides (not tracked)
├── templates/                    # Kubernetes manifests
│   ├── deployment.yaml           # TimescaleDB deployment
│   ├── service.yaml              # Database service
│   ├── cronjob.yaml              # Collector cronjob
│   └── configmap.yaml            # Configuration
└── files/
    └── init-db.sql               # Copy of main init-db.sql (keep in sync!)
```

### Grafana Dashboards
```
grafana/dashboards/               # Grafana dashboard JSON files
└── jupyterhub-demographics.json  # Main dashboard

chart/files/grafana/dashboards/   # Copy for Helm chart (keep in sync!)
└── jupyterhub-demographics.json
```

### History/Testing
```
history/
└── venv/                         # Python virtual environment for scripts
```

---

## 🗄️ Database Schema Overview

### Tables

#### `users` - User Information
- **Primary Key**: `email`
- **Key Fields**: `user_id`, `full_name`, `department`, `job_title`, `first_seen`, `last_seen`
- **Purpose**: Stores user profile information from Microsoft Graph API
- **Updated By**: `export_user_details*.py` scripts

#### `container_observations` - Raw Time Series Data
- **Type**: TimescaleDB Hypertable (partitioned by timestamp)
- **Primary Key**: `(user_email, pod_name, timestamp)`
- **Key Fields**: `timestamp`, `user_email`, `node_name`, `container_image`, `container_base`, `container_version`, `age_seconds`, `pod_name`
- **Purpose**: Raw observations of running containers (collected every 5 minutes)
- **Updated By**: `collector/collector.sh`
- **Retention**: DISABLED (keeps all data indefinitely)

### Views

#### `user_sessions` - Materialized View
- **Purpose**: Pre-computed user sessions from container observations
- **Session Definition**: Continuous observations on same pod/node with no >1 hour gap
- **Fields**: `user_email`, `pod_name`, `node_name`, `session_id`, `session_start`, `session_end`, `runtime_hours`, `container_base`, `container_version`
- **Refresh**: Automatically after each collector run
- **Note**: This is a MATERIALIZED VIEW - refresh with `REFRESH MATERIALIZED VIEW CONCURRENTLY user_sessions;`

#### `user_session_stats` - Regular View
- **Purpose**: Aggregated statistics per user
- **Fields**: `user_email`, `total_hours`, `gpu_hours`, `cpu_hours`, `total_sessions`, `applications_used`, `first_session`, `last_session`
- **GPU Detection**: Nodes without "cpu" in name = GPU, nodes with "cpu" = CPU

#### Continuous Aggregates (TimescaleDB)
- `hourly_node_stats` - Hourly statistics per Kubernetes node
- `hourly_image_stats` - Hourly statistics per container image
- Auto-maintained by TimescaleDB refresh policies

---

## 🔧 Development Conventions

### Python Scripts

1. **Always Use the Existing Virtual Environment**
   - Located at `history/venv/`
   - Activate with: `source history/venv/bin/activate`
   - Don't create new virtual environments

2. **Environment Configuration**
   - Load `.env` file using the `load_env_file()` pattern (see existing scripts)
   - Never hardcode credentials
   - Use `DB_*` environment variables for database connection
   - Database variables: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`

3. **Script Naming Conventions**
   - `export_*.py` - Scripts that export data to CSV
   - `test_*.py` - Scripts that test functionality without modifying production data
   - `migrate_*.sql` - Database migration scripts (include date if possible)
   - `fix_*.sql` - One-off data correction scripts

4. **CSV Export Conventions**
   - Fixed filenames (no timestamps) for regular exports: `user_usage_stats.csv`
   - Timestamped filenames for one-off exports: `user_details_20251024_123456.csv`
   - Always include headers
   - Use UTF-8 encoding

### SQL Scripts

1. **Idempotent Operations**
   - Always use `IF EXISTS` / `IF NOT EXISTS` where applicable
   - Scripts should be safe to run multiple times
   - Example:
     ```sql
     ALTER TABLE users ADD COLUMN IF NOT EXISTS department TEXT;
     ```

2. **Comments and Documentation**
   - Every major section should have a comment explaining its purpose
   - Document any non-obvious business logic
   - Include examples in comments where helpful

3. **Migration Scripts**
   - Create new files for migrations (don't modify init-db.sql directly for one-off changes)
   - Test on a small dataset first
   - Provide verification queries at the end
   - Example: `migrate_add_user_fields.sql`

### Data Transformations

1. **Special Cases to Remember**
   - **Fellowships Department**: Users with department="Fellowships" have their actual department embedded in job_title after a comma
   - Format: `"JOB_TITLE, Actual Department"`
   - Always split on comma and swap when encountering this
   - Example: `"GRAD TEACHING ASST, Siebel School Comp & Data Sci"` → job_title="GRAD TEACHING ASST", department="Siebel School Comp & Data Sci"

2. **GPU vs CPU Detection**
   - Nodes with "cpu" in the name (case-insensitive) = CPU-only nodes
   - All other nodes = GPU nodes
   - Pattern: `node_name NOT ILIKE '%cpu%'` for GPU hours

---

## 🔄 Common Operations

### Updating User Information from Microsoft Graph

**Incremental Update (default - only new users):**
```bash
export ACCESS_TOKEN="your_token_here"
python export_user_details_with_token.py
```

**Full Refresh (all users):**
```bash
export ACCESS_TOKEN="your_token_here"
python export_user_details_with_token.py --refresh
```

### Exporting User Usage Statistics
```bash
python export_user_usage_stats.py
# Outputs: user_usage_stats.csv
# Fields: fullname, email, department, jobtitle, gpu_hours, cpu_hours, total_hours, total_sessions, last_seen, favorite_container
```

### Database Migrations

1. Create a new migration file: `migrate_description_YYYYMMDD.sql`
2. Use idempotent operations (IF EXISTS, IF NOT EXISTS)
3. Test the migration:
   ```bash
   psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f migrate_description.sql
   ```
4. Update `chart/files/init-db.sql` if the changes should apply to new deployments

### Keep Files in Sync

When modifying these files, update BOTH locations:
- `init-db.sql` ↔️ `chart/files/init-db.sql`
- `grafana/dashboards/*.json` ↔️ `chart/files/grafana/dashboards/*.json`

---

## 📊 Data Collection Flow

1. **Every 5 minutes**: `collector/collector.sh` runs
   - Queries Kubernetes API for running JupyterHub pods
   - Extracts: user email, pod name, node name, container image, age
   - Inserts observations into `container_observations` table
   - Refreshes `user_sessions` materialized view
   - Updates `users` table with latest `last_seen` timestamp

2. **Hourly**: TimescaleDB continuous aggregate policies update
   - `hourly_node_stats` - node usage by hour
   - `hourly_image_stats` - container image usage by hour

3. **On-demand**: User detail synchronization
   - Run `export_user_details_with_token.py` to fetch latest user info from Microsoft Graph
   - Updates: `full_name`, `department`, `job_title` in `users` table

---

## 🐛 Troubleshooting Tips

### Python Script Issues
- Always use the virtual environment: `source history/venv/bin/activate`
- Check `.env` file exists and has correct credentials
- Verify database connectivity: `psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();"`

### Database Issues
- Check if TimescaleDB extension is enabled: `SELECT * FROM pg_extension WHERE extname = 'timescaledb';`
- View active policies: `SELECT * FROM timescaledb_information.jobs;`
- Check materialized view freshness: `SELECT schemaname, matviewname, last_refresh FROM pg_matviews;`

### Data Issues
- Session calculations depend on `user_sessions` materialized view being refreshed
- Missing job titles? Run `export_user_details_with_token.py --refresh`
- GPU hours showing as 0? Check node naming convention (nodes must NOT contain "cpu" for GPU detection)

---

## ✅ Pre-Flight Checklist for Major Changes

Before making significant changes:

- [ ] Read this document thoroughly
- [ ] Understand the current schema (check `init-db.sql`)
- [ ] Identify which files need to be kept in sync
- [ ] Create a backup or migration script if modifying schema
- [ ] Use `IF EXISTS` / `IF NOT EXISTS` for idempotent operations
- [ ] Test on a small dataset first
- [ ] Provide rollback instructions
- [ ] Update both `init-db.sql` and `chart/files/init-db.sql` if needed
- [ ] Update this AGENTS.md if you learned new important rules

---

## 🔮 Future Agent Instructions

**Dear Future AI Agent:**

If you discover new important patterns, conventions, or safety rules while working on this codebase, please update this document in the relevant section. This helps maintain institutional knowledge across conversations.

When adding new rules:
1. Add them in the appropriate section (or create a new section if needed)
2. Explain the **why** behind the rule, not just the **what**
3. Provide examples where helpful
4. Mark critical safety rules with 🚨
5. Keep the tone helpful and conversational

Remember: This codebase tracks valuable long-term research data. Preservation and accuracy are more important than convenience.

---

**Last Updated**: 2025-10-26  
**Version**: 1.0  
**Maintained By**: AI Agents working with the JupyterHub Metrics project team
