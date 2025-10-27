# Security Configuration Guide

## Overview

This project uses a centralized `.env` configuration file to manage all sensitive information (database credentials, API keys, passwords, etc.). This guide explains how to properly set up and maintain security for the JupyterHub Metrics system.

## Quick Start

### 1. Create Your Local Configuration

```bash
# Copy the template file to create your local configuration
cp .env.example .env
```

### 2. Edit `.env` with Real Values

Edit the newly created `.env` file and fill in your actual configuration values:

```bash
# Database Configuration
DB_HOST=your-postgres-host
DB_PORT=5432
DB_NAME=jupyterhub_metrics
DB_USER=your-db-user
DB_PASSWORD=your-secure-password

# Grafana Configuration
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=your-secure-password
GRAFANA_PORT=3000

# Other configurations...
```

### 3. Protect Your `.env` File

The `.env` file is already in `.gitignore` and should **NEVER** be committed to version control. Keep it secure:

```bash
# Check that .env is properly ignored
git status  # Should NOT list .env

# Set restrictive permissions (optional but recommended)
chmod 600 .env
```

## File Organization

### Configuration Files

| File | Committed | Purpose | Contains Secrets |
|------|-----------|---------|------------------|
| `.env.example` | ✅ Yes | Template for configuration | ❌ No (examples only) |
| `.env` | ❌ No (in .gitignore) | Your actual configuration | ⚠️ Yes (keep private) |
| `.gitignore` | ✅ Yes | Git ignore rules | ❌ No |

### Environment Variables by Component

#### Database (TimescaleDB/PostgreSQL)

```bash
DB_HOST          # Hostname or IP
DB_PORT          # Port number (default: 5432)
DB_NAME          # Database name
DB_USER          # Database user
DB_PASSWORD      # Database password
```

#### Grafana

```bash
GRAFANA_ADMIN_USER       # Grafana admin username
GRAFANA_ADMIN_PASSWORD   # Grafana admin password
GRAFANA_PORT             # Grafana port (default: 3000)
```

#### Collector Service

```bash
COLLECTION_INTERVAL      # Seconds between metric collections
KUBECTL_CONTEXT          # Kubernetes context name
NAMESPACE                # Kubernetes namespace to monitor
```

#### Kubernetes Deployment (Optional)

```bash
K8S_NAMESPACE            # K8s namespace for deployment
TIMESCALEDB_STORAGE_SIZE # Storage allocation
GRAFANA_STORAGE_SIZE     # Storage allocation
INGRESS_HOST             # Ingress hostname
```

#### InfluxDB (For Migration Scripts)

```bash
INFLUX_HOST              # InfluxDB hostname
INFLUX_PORT              # InfluxDB port
INFLUX_USER              # InfluxDB username
INFLUX_PASSWORD          # InfluxDB password
INFLUX_DATABASE          # Database name
INFLUX_SSL               # Use SSL (true/false)
INFLUX_VERIFY_SSL        # Verify SSL cert (true/false)
```

## How Configuration is Used

### Shell Scripts (collector.sh, backup scripts, etc.)

All shell scripts are designed to work in multiple environments:

**For Docker Compose:**

```bash
# .env file exists, so config-loader.sh is sourced
source ./config-loader.sh

# All variables are now available and validated
echo "Connecting to $DB_HOST as $DB_USER"
```

**For Kubernetes:**

- No `.env` file exists in the container
- Environment variables are injected via Kubernetes Secrets/ConfigMaps
- Scripts set safe defaults and validate required variables are set

The `config-loader.sh` script (Docker Compose only):

- Loads `.env` file from project root
- Validates that required variables are set
- Validates that port numbers are numeric
- Exports all variables for use in child processes
- Fails with clear error messages if configuration is invalid

**Example: collector.sh works in both environments**

```bash
# If .env exists (Docker Compose), load it
if [[ -f "$ENV_FILE" ]]; then
    source "${SCRIPT_DIR}/config-loader.sh"
fi

# Set defaults for Kubernetes environment
DB_HOST="${DB_HOST:-localhost}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Validate required variables
if [[ -z "$DB_PASSWORD" ]]; then
    echo "ERROR: DB_PASSWORD not set"
    exit 1
fi
```

### Docker Compose

The `docker-compose.yml` uses Docker's built-in `.env` file support:

```yaml
environment:
  POSTGRES_DB: ${DB_NAME}
  POSTGRES_USER: ${DB_USER}
  POSTGRES_PASSWORD: ${DB_PASSWORD}
```

When running `docker-compose up`, Docker automatically loads variables from `.env`.

### Python Scripts (Migration/Import)

Python scripts read environment variables directly:

```python
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
```

The wrapper scripts (`import.sh`, `inspect.sh`) source `.env` before calling Python, ensuring all environment variables are set.

### Grafana Datasource Configuration

The Grafana datasource configuration now uses environment variable placeholders:

```yaml
datasources:
  - name: TimescaleDB
    type: postgres
    url: ${DB_HOST}:${DB_PORT}
    user: ${DB_USER}
    secureJsonData:
      password: ${DB_PASSWORD}
    jsonData:
      database: ${DB_NAME}
```

Environment variables are substituted at runtime when containers start.

## Security Best Practices

### 1. Keep `.env` File Secure

```bash
# NEVER commit .env to version control
git status  # Verify .env is not listed

# Set restrictive file permissions
chmod 600 .env

# Keep `.env` file in a secure location
# Back it up securely (not on public storage)
```

### 2. Generate Strong Passwords

```bash
# Use OpenSSL or similar to generate secure passwords
openssl rand -base64 32

# Example output:
# aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890AbCdEfG=

# Add this to .env
DB_PASSWORD=aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890AbCdEfG
```

### 3. Rotate Credentials Regularly

1. Generate new password
2. Update `.env` with new value
3. Update password in actual services (database, Grafana, etc.)
4. Restart affected containers/services
5. Keep old credentials temporarily in case of issues
6. Verify everything works, then securely delete old credentials

### 4. Different Configurations for Different Environments

Use different `.env` files for different environments:

```bash
# Development
.env                    # Your local development config

# Production (keep in secure vault, not in git)
.env.prod              # Production configuration (NOT in git)
.env.staging           # Staging configuration (NOT in git)
```

To use a different config file:

```bash
# For shell scripts, copy your config
cp .env.prod .env
./collector.sh

# Or modify scripts to load specific file
source .env.prod
```

### 5. Monitor Configuration Changes

- Keep track of who has access to `.env`
- Log credential rotation dates
- Document any configuration changes
- Use a secure vault (like HashiCorp Vault, AWS Secrets Manager) in production

## Troubleshooting Configuration Issues

### Error: "Configuration file not found"

```text
ERROR: Configuration file not found: /path/to/.env
Please create a .env file by copying .env.example:
  cp .env.example .env
Then edit .env with your actual configuration values.
```

**Solution:** Run the commands shown in the error message.

### Error: "Required configuration variables not set"

```text
ERROR: The following required configuration variables are not set:
  - DB_PASSWORD
  - GRAFANA_ADMIN_PASSWORD
```

**Solution:** Edit `.env` and ensure all required variables have values.

### Error: "Port must be a number"

```text
ERROR: DB_PORT must be a number, got: not_a_number
```

**Solution:** Check `.env` and ensure port values are numeric (e.g., `5432` not `"5432"`).

### Docker Compose not picking up `.env` values

**Solution:**

1. Verify `.env` file exists in the same directory as `docker-compose.yml`
2. Run `docker-compose config` to see if variables are substituted
3. Ensure variable names in `.env` match those in `docker-compose.yml`

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy

on: [push]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Create .env file
        run: |
          cat > .env << EOF
          DB_HOST=${{ secrets.DB_HOST }}
          DB_NAME=${{ secrets.DB_NAME }}
          DB_USER=${{ secrets.DB_USER }}
          DB_PASSWORD=${{ secrets.DB_PASSWORD }}
          GRAFANA_ADMIN_USER=${{ secrets.GRAFANA_ADMIN_USER }}
          GRAFANA_ADMIN_PASSWORD=${{ secrets.GRAFANA_ADMIN_PASSWORD }}
          EOF
      
      - name: Deploy
        run: docker-compose up -d
```

### Kubernetes Secrets

For Kubernetes deployments, use the `k8s/deploy.sh` script which reads from `.env` and creates K8s Secrets:

```bash
./k8s/deploy.sh

# This will:
# 1. Read credentials from .env
# 2. Create a Kubernetes Secret
# 3. Configure deployments to use the secret
```

## Migration from Old Configuration

If you're upgrading from hardcoded configurations, follow these steps:

1. **Create `.env` file:**

   ```bash
   cp .env.example .env
   ```

2. **Extract credentials from existing files:**
   - From `docker-compose.yml` (hardcoded values)
   - From `k8s/config.env` (existing deployment config)
   - From application configuration files

3. **Update `.env` with extracted values:**

   ```bash
   nano .env
   ```

4. **Verify scripts load correctly:**

   ```bash
   # Test collector script in Docker Compose
   docker-compose up collector  # Should work if config is correct
   
   # Test backup script
   ./dump-database.sh  # Should work without errors
   ```

5. **Update version control:**

   ```bash
   # Verify .env is in .gitignore
   git status
   
   # Commit updated scripts and .env.example
   git add .gitignore collector.sh dump-database.sh restore-database.sh
   git add docker-compose.yml .env.example
   git commit -m "feat: Centralize configuration management"
   ```

6. **Remove hardcoded credentials from git history:**

   ```bash
   # Use git-filter-branch or BFG repo cleaner to remove sensitive data
   # See: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
   ```

## Security Audit Checklist

- [ ] `.env` file exists and is NOT committed to git
- [ ] `.gitignore` includes `.env` and other sensitive patterns
- [ ] All database passwords are strong (16+ characters, mixed types)
- [ ] All Grafana passwords are strong and different from DB passwords
- [ ] `DB_PASSWORD` and `GRAFANA_ADMIN_PASSWORD` are NOT used in `.env.example`
- [ ] `.env` file has restrictive permissions (`chmod 600`)
- [ ] No plaintext credentials in docker-compose.yml
- [ ] No plaintext credentials in shell scripts
- [ ] No plaintext credentials in Python scripts
- [ ] All scripts load from `config-loader.sh` or source `.env`
- [ ] Backup scripts are included in `.gitignore`
- [ ] Historical backups are stored securely (not in git)
- [ ] Kubernetes secrets are created from `.env`, not hardcoded

## Support and Questions

For security concerns or questions:

1. Review this guide first
2. Check `.env.example` for configuration templates
3. Run `VERBOSE=1 ./config-loader.sh` to debug configuration loading
4. See `.gitignore` for files that are protected from git

## Related Files

- `.env.example` - Configuration template with documentation
- `.env` - Your local configuration (keep private!)
- `.gitignore` - Git ignore rules for sensitive files
- `config-loader.sh` - Configuration loader utility
- `docker-compose.yml` - Docker service definitions using `.env`
- `collector.sh` - Metrics collector using centralized config
- `dump-database.sh` - Backup script using centralized config
- `restore-database.sh` - Restore script using centralized config
- `grafana/provisioning/datasources/timescaledb.yml` - Datasource config using env vars
- `history/import.sh` - Migration script wrapper using centralized config
