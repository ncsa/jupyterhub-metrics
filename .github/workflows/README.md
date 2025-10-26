# GitHub Workflows Documentation

This directory contains GitHub Actions workflows for CI/CD, code quality, and security scanning for the JupyterHub Metrics project.

## Workflows Overview

### Docker & Container Management

#### `docker-collector.yml` - Collector Docker Image
**Triggers:**
- Push to `main` branch when `collector/**` files change
- Release published
- Manual dispatch

**Actions:**
- Builds the collector Docker image from `collector/Dockerfile`
- Tags images appropriately:
  - `latest` for main branch
  - Version tags (e.g., `1.0.0`, `1.0`, `1`) for releases
  - SHA-based tags for traceability
- Pushes to GitHub Container Registry (`ghcr.io`)
- Multi-platform build (amd64, arm64)
- Generates build attestations for supply chain security

**Required Permissions:**
- `contents: read`
- `packages: write`

**Usage:**
```bash
# Pull the latest image
docker pull ghcr.io/ncsa/jupyterhub-metrics/collector:latest

# Pull a specific version
docker pull ghcr.io/ncsa/jupyterhub-metrics/collector:1.0.0
```

---

### Helm Chart Management

#### `helm-chart.yml` - Helm Chart Linting and Publishing
**Triggers:**
- Push to `main` branch when `chart/**` files change
- Pull requests affecting `chart/**`
- Release published
- Manual dispatch

**Actions:**

**Lint Job:**
- Runs `chart-testing` (ct) linter
- Runs `helm lint`
- Validates chart values with dry-run template rendering

**Package & Push Job (releases only):**
- Updates chart version from release tag
- Packages Helm chart
- Pushes to GitHub Container Registry as OCI artifact
- Uploads chart as release asset

**Usage:**
```bash
# Install the chart from GHCR
helm install jupyterhub-metrics oci://ghcr.io/ncsa/charts/jupyterhub-metrics --version 1.0.0

# Or download from release assets
wget https://github.com/ncsa/jupyterhub-metrics/releases/download/v1.0.0/jupyterhub-metrics-1.0.0.tgz
helm install jupyterhub-metrics ./jupyterhub-metrics-1.0.0.tgz
```

---

### Code Quality & Linting

#### `python-lint.yml` - Python Code Quality
**Triggers:**
- Push to `main` when `**.py` files change
- Pull requests affecting `**.py`
- Manual dispatch

**Actions:**
- Tests against Python 3.9, 3.10, 3.11, 3.12
- **Black**: Code formatting check
- **isort**: Import sorting check
- **Flake8**: Style guide enforcement (PEP 8)
- **Pylint**: Static analysis
- **mypy**: Type checking
- **Bandit**: Security vulnerability scanning

**Security Job:**
- Scans Python code for security issues
- Uploads Bandit security report as artifact

---

#### `shell-lint.yml` - Shell Script Linting
**Triggers:**
- Push to `main` when `**.sh` files change
- Pull requests affecting `**.sh`
- Manual dispatch

**Actions:**
- Runs ShellCheck on all shell scripts
- Verifies scripts are executable
- Excludes venv and .git directories

---

#### `sql-lint.yml` - SQL Linting
**Triggers:**
- Push to `main` when `**.sql` files change
- Pull requests affecting `**.sql`
- Manual dispatch

**Actions:**
- Uses SQLFluff to lint SQL files
- Configured for PostgreSQL dialect
- Checks syntax and style

---

#### `ci.yml` - Continuous Integration Checks
**Triggers:**
- Push to `main` branch
- Pull requests
- Manual dispatch

**Jobs:**
1. **Markdown Linting**: Lints all `.md` files
2. **YAML Linting**: Validates YAML syntax and style
3. **JSON Validation**: Validates all JSON files (especially Grafana dashboards)
4. **File Permissions**: Ensures scripts are executable

---

### Security Scanning

#### `security-scan.yml` - Comprehensive Security Scanning
**Triggers:**
- Push to `main` branch
- Pull requests
- Weekly schedule (Mondays at 00:00 UTC)
- Manual dispatch

**Jobs:**

1. **CodeQL Analysis**: 
   - Static application security testing (SAST)
   - Detects common vulnerabilities in Python code
   - Results appear in Security tab

2. **Trivy Container Scan**:
   - Scans Docker images for vulnerabilities
   - Reports CRITICAL and HIGH severity issues
   - Uploads results to GitHub Security tab

3. **TruffleHog Secret Scan**:
   - Scans git history for accidentally committed secrets
   - Only reports verified secrets to reduce false positives

4. **Dependency Review** (PR only):
   - Reviews dependency changes in pull requests
   - Fails on moderate or higher severity vulnerabilities

**Required Permissions:**
- `contents: read`
- `security-events: write`

---

### Release Management

#### `release.yml` - Release Workflow
**Triggers:**
- Push of version tags (e.g., `v1.0.0`)
- Manual dispatch with version input

**Actions:**
- Creates GitHub release
- Extracts changelog from `CHANGELOG.md`
- Generates release notes
- Validates version consistency across chart files

**Creating a Release:**
```bash
# 1. Update version in chart/Chart.yaml
# 2. Update CHANGELOG.md
# 3. Commit changes
git add chart/Chart.yaml CHANGELOG.md
git commit -m "Prepare release v1.0.0"

# 4. Create and push tag
git tag v1.0.0
git push origin v1.0.0

# The workflow will automatically:
# - Create GitHub release
# - Build and push Docker images
# - Package and publish Helm chart
```

---

### Dependency Management

#### `dependabot.yml` - Automated Dependency Updates
**Configuration for:**
- **GitHub Actions**: Weekly updates on Mondays
- **Docker**: Weekly base image updates
- **Python**: Weekly package updates

**Behavior:**
- Opens PRs automatically for dependency updates
- Labels PRs by type (`dependencies`, `github-actions`, `docker`, `python`)
- Limits concurrent PRs to prevent spam

---

## Required Secrets

These workflows use built-in GitHub secrets and don't require additional configuration:

- `GITHUB_TOKEN`: Automatically provided by GitHub Actions
  - Used for: Pushing to GHCR, creating releases, uploading artifacts

## Branch Protection Recommendations

Suggested branch protection rules for `main`:

1. Require pull request reviews before merging
2. Require status checks to pass:
   - `lint` (from python-lint.yml)
   - `lint` (from helm-chart.yml)
   - `shellcheck` (from shell-lint.yml)
   - `markdown-lint` (from ci.yml)
   - `check-secrets` (from ci.yml)
3. Require branches to be up to date before merging
4. Include administrators in restrictions

## Monitoring Workflows

### View Workflow Runs
- Navigate to **Actions** tab in GitHub repository
- Filter by workflow name or status

### Artifacts
Some workflows generate artifacts:
- **bandit-security-report**: Python security scan results (python-lint.yml)

### Security Alerts
Security findings appear in:
- **Security** tab → **Code scanning alerts** (CodeQL, Trivy)
- **Security** tab → **Dependabot alerts** (dependency vulnerabilities)

## Troubleshooting

### Workflow Failures

**Docker Build Fails:**
- Check `collector/Dockerfile` syntax
- Verify base image availability
- Check GHCR permissions

**Helm Lint Fails:**
- Run locally: `helm lint chart/`
- Check `chart/values.yaml` syntax

**Python Lint Fails:**
- Run locally: `flake8 *.py`
- Fix formatting: `black *.py`
- Fix imports: `isort *.py`

**Security Scan Fails:**
- Review findings in Security tab
- Update vulnerable dependencies
- Address code vulnerabilities

### Manual Workflow Dispatch

Most workflows support manual triggering:
1. Go to **Actions** tab
2. Select workflow
3. Click **Run workflow**
4. Choose branch and parameters

## Best Practices

1. **Always run linters locally before pushing:**
   ```bash
   # Python
   black *.py && isort *.py && flake8 *.py
   
   # Shell
   shellcheck *.sh
   
   # Helm
   helm lint chart/
   ```

2. **Test Docker builds locally:**
   ```bash
   docker build -t collector:test ./collector
   ```

3. **Review security scan results regularly**

4. **Keep dependencies up to date** (review Dependabot PRs)

5. **Follow conventional commits** for clear history:
   - `feat:` New features
   - `fix:` Bug fixes
   - `docs:` Documentation
   - `ci:` CI/CD changes
   - `refactor:` Code refactoring

## Adding New Workflows

When adding new workflows:

1. Place in `.github/workflows/`
2. Use descriptive names
3. Add appropriate triggers
4. Document in this README
5. Test with manual dispatch first
6. Set appropriate permissions (principle of least privilege)

---

**For more information:**
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow syntax](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)
