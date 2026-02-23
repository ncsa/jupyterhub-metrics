# AGENTS.md - Guidelines for AI Agents Working on JupyterHub Metrics

This document contains important rules, conventions, and structural information for AI agents (like Claude) working on this codebase. These guidelines help ensure consistency, safety, and efficiency when making changes.

---

## 🚨 Critical Safety Rules

### Git Commit Safety

1. **ONLY COMMIT FILES YOU ACTIVELY WORKED ON** - This is critical
   - When committing changes, ONLY stage and commit the specific files you created or modified
   - NEVER use `git add -A` or `git add .` without carefully reviewing what will be committed
   - NEVER commit files that were modified/added/deleted by other processes or users
   - Always use `git status` to review changes before committing
   - Use selective staging: `git add <specific-file>` for only the files you worked on
   - Example workflow:

     ```bash
     # Review all changes first
     git status
     
     # Only stage the specific files you modified
     git add docker-compose.yml
     git add AGENTS.md
     
     # Verify what will be committed
     git status
     
     # Then commit
     git commit -m "Update docker-compose to use chart/files/grafana"
     ```

2. **NEVER PUSH TO REMOTE** - The user handles all git push operations
   - You may create commits with `git commit`
   - NEVER run `git push` or `git push origin <branch>`
   - The user will review and push commits when ready
   - If the user asks you to "commit changes", only run `git commit`, not `git push`

3. **ALWAYS USE `--no-pager` WITH GIT COMMANDS** - Prevents hanging on interactive prompts
   - Git commands can open interactive pagers (like `less` or `more`) which will hang waiting for user input
   - Always use `git --no-pager <command>` to prevent this
   - Examples:

     ```bash
     git --no-pager status
     git --no-pager log
     git --no-pager diff
     git --no-pager show
     ```

   - Exception: Simple commands like `git add`, `git commit` don't need `--no-pager`

4. **AMEND COMMITS WHEN FIXING ERRORS IN THE SAME CHAT** - Keep history clean
   - If you're fixing an error or making adjustments to work done in the same conversation, use `git commit --amend`
   - Only create new commits if the previous work has been pushed to remote
   - Check if commits have been pushed: `git --no-pager log origin/main..HEAD`
   - Example:

     ```bash
     # Make fix to previous work
     git add chart/files/grafana/dashboards/jupyterhub-demographics.json
     
     # Amend the previous commit instead of creating a new one
     git commit --amend --no-edit
     ```

   - Use `--amend -m "new message"` if you need to update the commit message

### Helm Chart Management

1. **UPDATE Chart.yaml VERSION AFTER CHANGES** - Keep versions in sync
   - Any changes to files in the `chart/` directory require a version bump in `chart/Chart.yaml`
   - Version bump guidelines (follow Semantic Versioning):
     - **PATCH** (e.g., 1.2.3 → 1.2.4): Bug fixes, dashboard tweaks, small corrections
     - **MINOR** (e.g., 1.2.4 → 1.3.0): New features, new dashboards, new configuration options
     - **MAJOR** (e.g., 1.3.0 → 2.0.0): Breaking changes, schema changes, incompatible updates
   - Example changes:

     ```yaml
     # chart/Chart.yaml
     version: 1.3.0  # Bump this after changes
     ```

2. **ONLY BUMP VERSION IF NOT PUSHED** - Check before versioning
   - Before bumping the chart version, verify the current version hasn't been pushed
   - Check for unpushed commits: `git --no-pager log origin/main..HEAD`
   - Check if the version tag exists: `git --no-pager tag -l "v1.3.0"`
   - If the version is already pushed/tagged, you MUST bump to the next version
   - If not pushed yet, you can amend the existing commit with new changes

3. **MAINTAIN values.schema.json** - Keep schema up to date
   - The `chart/values.schema.json` file must be kept in sync with `chart/values.yaml`
   - Add JSON schema definitions for any new values added to `values.yaml`
   - Include descriptions, types, and constraints for all configuration options
   - This enables validation and provides documentation for chart users
   - When making fields optional or allowing null, update the type to: `"type": ["string", "null"]` or `"type": ["object", "null"]`
   - Always update `Chart.yaml` with schema changes in the `artifacthub.io/changes` annotation
   - Location: `chart/values.schema.json`

4. **UPDATE ARTIFACTHUB.IO CHANGES** - Document changes in Chart.yaml
   - Helm charts can include an `artifacthub.io/changes` annotation in `Chart.yaml`
   - Document ALL changes made in the version, even small ones
   - Format:

     ```yaml
     annotations:
       artifacthub.io/changes: |
         - kind: added
           description: Added Users by College and Users by Application tables to demographics dashboard
         - kind: changed
           description: Updated all demographics tables to show GPU/CPU hours
         - kind: fixed
           description: Fixed incorrect column widths in dashboard tables
     ```

   - Valid kinds: `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`

5. **MAINTAIN CHANGELOG.md** - Document all releases
   - Keep a `CHANGELOG.md` file in the `chart/` directory
   - The version in the changelog MUST match the version in `Chart.yaml`
   - Follow [Keep a Changelog](https://keepachangelog.com/) format
   - Include sections: Added, Changed, Deprecated, Removed, Fixed, Security
   - Example:

     ```markdown
     ## [1.3.0] - 2025-11-03
     
     ### Added
     - Users by College table in demographics dashboard
     - Users by Application table in demographics dashboard
     
     ### Changed
     - Updated all demographics tables to display GPU Hours, CPU Hours, and Total Hours
     - Reorganized demographics dashboard into 2x2 grid layout
     ```

   - Location: `chart/CHANGELOG.md`

### Database Safety

1. **NEVER DROP TABLES** - Especially when upgrading or modifying schemas
   - Always use `ALTER TABLE` to modify existing tables
   - Use `IF NOT EXISTS` when creating new tables or columns
   - Preserve all existing data during schema changes
   - Example: Use `ALTER TABLE users ADD COLUMN IF NOT EXISTS department TEXT;` instead of dropping and recreating

2. **NEVER DELETE DATA** - Unless explicitly requested by the user
   - Retention policies are **DISABLED** - keep all data indefinitely
   - DO NOT add retention policies to migration files
   - Any deletion scripts must be clearly marked and require explicit confirmation
   - When modifying data, use UPDATE instead of DELETE/INSERT where possible

3. **Always Use Transactions for Data Modifications**
   - Wrap multi-step database changes in transactions
   - Test queries on a small dataset before running on full table
   - Provide rollback instructions for any major changes

---

## 📁 Project Structure

### Root Directory

```text
jupyterhub-metrics/
├── .env                          # Database credentials and configuration (DO NOT COMMIT)
├── .env.example                  # Template for environment variables
├── AGENTS.md                     # This file - guidelines for AI agents
└── README.md                     # Project documentation
```

**IMPORTANT**: Database migrations and Grafana dashboards are maintained in `chart/files/` - see Helm Chart section below.

### Python Scripts

```text
├── export_user_details.py              # Fetch user details from MS Graph (device auth)
├── export_user_details_with_token.py   # Fetch user details from MS Graph (token auth)
├── export_user_usage_stats.py          # Export user usage statistics to CSV
├── test_*.py                            # Test scripts (don't modify production data)
```

### Collector

```text
collector/
├── collector.sh                  # Main data collection script (runs every 5 minutes)
└── Dockerfile                    # Container for running collector
```

### Helm Chart (Source of Truth for Config Files)

```text
chart/
├── Chart.yaml                    # Helm chart metadata
├── values.yaml                   # Default configuration values
├── cori-dev.yaml                 # Environment-specific overrides (not tracked)
├── templates/                    # Kubernetes manifests
│   ├── deployment.yaml           # TimescaleDB deployment
│   ├── service.yaml              # Database service
│   ├── cronjob.yaml              # Collector cronjob
│   └── configmap.yaml            # Configuration
└── files/                        # **PRIMARY SOURCE** for all config files
    ├── migrations/               # golang-migrate numbered migration files
    │   ├── 000001_initial_schema.up.sql
    │   ├── 000001_initial_schema.down.sql
    │   ├── 000002_add_college_column.up.sql
    │   ├── 000002_add_college_column.down.sql
    │   ├── 000003_fix_fellowships_department.up.sql
    │   ├── 000003_fix_fellowships_department.down.sql
    │   ├── 000004_gpu_detection_update.up.sql
    │   └── 000004_gpu_detection_update.down.sql
    └── grafana/
        ├── provisioning/         # Grafana provisioning configs
        └── dashboards/           # Grafana dashboard JSON files
            └── jupyterhub-demographics.json
```

**CRITICAL**: The `chart/files/` directory is the single source of truth for:

- Database migrations (`migrations/` directory — golang-migrate numbered files)
- Grafana dashboards and provisioning
- All configuration files used by both Kubernetes and local docker-compose

Edit files in `chart/files/` directly. Do NOT create duplicates in the root directory.

### History/Testing

```text
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
   - `chart/files/migrations/{version}_{description}.up.sql` - golang-migrate forward migrations
   - `chart/files/migrations/{version}_{description}.down.sql` - golang-migrate rollback migrations

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
   - Create new numbered migration files in `chart/files/migrations/`
   - Test on a small dataset first
   - Provide verification queries at the end
   - Example: `migrations/migrate_add_user_fields.sql`

### YAML Files (values.yaml, workflows)

1. **Comment Spacing - CRITICAL**
   - **ALWAYS use 2 spaces before inline comments** (the `#` character)
   - Correct: `key: "value"  # comment` (2 spaces)
   - Wrong: `key: "value" # comment` (1 space - will fail yamllint)
   - This applies to ALL YAML files, especially `chart/values.yaml`
   - Lines to watch in values.yaml: 59, 151, 199 (these have inline comments)
   - When using Edit tool, preserve exact spacing of inline comments

2. **Why This Matters**
   - yamllint requires at least 2 spaces before inline comments
   - Helm linting will fail if spacing is incorrect
   - CI/CD workflows check this automatically

### Data Transformations

1. **Special Cases to Remember**
   - **Fellowships Department**: Users with department="Fellowships" have their actual department embedded in job_title after a comma
   - Format: `"JOB_TITLE, Actual Department"`
   - Always split on comma and swap when encountering this
   - Example: `"GRAD TEACHING ASST, Siebel School Comp & Data Sci"` → job_title="GRAD TEACHING ASST", department="Siebel School Comp & Data Sci"

2. **"Active Now" queries — always use `container_observations`**
   - `user_sessions.session_end = MAX(observation_timestamp)` — always a few minutes in the past
   - `session_end > NOW()` is therefore **always false** and returns 0
   - For "who is running right now" use: `FROM container_observations WHERE timestamp >= NOW() - INTERVAL '10 minutes'`
   - This works because the collector inserts a row every 5 minutes per running pod

3. **Time-series "users over time" — always use `container_observations`**
   - `user_sessions` with `session_start >= $__timeFrom()` misses long-running sessions that started before the window (the majority of users)
   - Use `FROM container_observations WHERE timestamp >= $__timeFrom() AND timestamp <= $__timeTo()` with `time_bucket('1 hour', timestamp)` — this correctly counts who was active in each bucket regardless of when their session started

4a. **Range queries on `user_sessions` — use overlap condition, not containment**
   - WRONG: `session_start >= $__timeFrom() AND session_end <= $__timeTo()` — only returns sessions that both started AND ended within the window (misses long-running sessions)
   - CORRECT: `session_start <= $__timeTo() AND session_end >= $__timeFrom()` — returns any session that overlaps with the window
   - Use the overlap condition for all stat panels (GPU Hours, CPU Hours, Total Hours, Total Users, Total Sessions, etc.) and table panels that aggregate over a time range

4. **GPU vs CPU Detection**
   - GPU nodes: nodes whose name matches `v100`, `a100`, `h100`, or `h200` (case-insensitive)
   - CPU nodes: all other nodes (does NOT match any GPU model pattern)
   - Pattern: `(node_name ILIKE '%v100%' OR node_name ILIKE '%a100%' OR node_name ILIKE '%h100%' OR node_name ILIKE '%h200%')` for GPU hours
   - When a new GPU model is added to the cluster, add its pattern to all dashboards and create a new migration updating `user_session_stats`

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

Migrations are managed with **golang-migrate**. Migration files live in `chart/files/migrations/`
and are tracked in the `schema_migrations` database table. Both docker-compose and Helm apply
migrations automatically on startup/upgrade.

**Adding a new migration:**

1. Create two files in `chart/files/migrations/`:
   - `{version}_{description}.up.sql` — forward migration
   - `{version}_{description}.down.sql` — rollback (or `SELECT 1;` with comment if not reversible)
   - Versions are zero-padded integers: `000005`, `000006`, etc.
   - Use idempotent operations (`IF EXISTS`, `IF NOT EXISTS`, `CREATE OR REPLACE`)
2. Test locally:

   ```bash
   docker compose up migrate
   # Check version applied:
   docker run --rm -v ./chart/files/migrations:/migrations migrate/migrate \
     -path=/migrations \
     -database "postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=disable" \
     version
   ```

3. Commit both `.up.sql` and `.down.sql` files — Helm will package them into the migrations ConfigMap
   and apply them on next `helm upgrade`.

**Stamping an existing database** (for databases already running the schema before a migration was added):

```bash
docker run --rm -v ./chart/files/migrations:/migrations migrate/migrate \
  -path=/migrations \
  -database "postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=disable" \
  force {version}
```

**DO NOT** modify `chart/files/init-db.sql` for incremental schema changes — it is a legacy reference
only. All schema evolution happens through numbered migration files.

### Configuration Files - Single Source of Truth

**All configuration files are maintained in `chart/files/`:**

- Database migrations: Edit/add files in `chart/files/migrations/` directly
- Grafana dashboards: Edit `chart/files/grafana/dashboards/*.json` directly
- Grafana provisioning: Edit `chart/files/grafana/provisioning/*` directly

Both `docker-compose.yml` and Kubernetes deployments reference these files.
**Do NOT create duplicate copies in the root directory.**

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
- [ ] Understand the current schema (check `chart/files/migrations/`)
- [ ] Identify which files need to be kept in sync
- [ ] Create a backup or migration script if modifying schema
- [ ] Use `IF EXISTS` / `IF NOT EXISTS` for idempotent operations
- [ ] Test on a small dataset first
- [ ] Provide rollback instructions
- [ ] Add new migration files to `chart/files/migrations/` if schema changes are needed
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

**Last Updated**: 2026-02-23
**Version**: 1.2
**Maintained By**: AI Agents working with the JupyterHub Metrics project team
