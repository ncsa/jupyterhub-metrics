# GitHub Workflows Summary

## Quick Reference

This project now includes 8 comprehensive GitHub Actions workflows plus Dependabot configuration.

### Workflows Created

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| **Docker Collector** | `docker-collector.yml` | Push to main (collector/**), releases | Build & push collector image to GHCR |
| **Helm Chart** | `helm-chart.yml` | Push/PR (chart/**), releases | Lint & publish Helm charts |
| **Python Linting** | `python-lint.yml` | Push/PR (**.py) | Code quality & security (Black, Flake8, Pylint, Bandit) |
| **Shell Linting** | `shell-lint.yml` | Push/PR (**.sh) | ShellCheck for bash scripts |
| **SQL Linting** | `sql-lint.yml` | Push/PR (**.sql) | SQLFluff for SQL files |
| **CI Checks** | `ci.yml` | Push/PR, always | Markdown, YAML, JSON, permissions, secrets |
| **Security Scan** | `security-scan.yml` | Push/PR, weekly | CodeQL, Trivy, TruffleHog, dependency review |
| **Release** | `release.yml` | Version tags (v*) | Create releases, validate versions |

### Dependabot Configuration

Automated dependency updates for:

- GitHub Actions (weekly)
- Docker base images (weekly)
- Python packages (weekly)

## Image Registry

### Collector Image

```bash
# Latest
ghcr.io/ncsa/jupyterhub-metrics/collector:latest

# Specific version
ghcr.io/ncsa/jupyterhub-metrics/collector:1.0.0
```

### Helm Chart

```bash
# Install from GHCR OCI registry
helm install jupyterhub-metrics \
  oci://ghcr.io/ncsa/charts/jupyterhub-metrics \
  --version 1.0.0
```

## Release Process

1. **Update versions:**

   ```bash
   # Update chart/Chart.yaml (version and appVersion)
   # Update CHANGELOG.md
   ```

2. **Commit and tag:**

   ```bash
   git add chart/Chart.yaml CHANGELOG.md
   git commit -m "chore: prepare release v1.0.0"
   git tag v1.0.0
   git push origin main
   git push origin v1.0.0
   ```

3. **Automated actions:**
   - ✅ GitHub release created
   - ✅ Docker image built and pushed (with version tags)
   - ✅ Helm chart packaged and pushed to GHCR
   - ✅ Helm chart added as release asset

## Security Features

### Automated Scanning

- **CodeQL**: Weekly code security analysis
- **Trivy**: Container vulnerability scanning
- **TruffleHog**: Secret detection in git history
- **Bandit**: Python security issues
- **Dependency Review**: PR-based dependency checks

### Supply Chain Security

- Build attestations for Docker images
- Multi-platform builds (amd64, arm64)
- SBOM generation support ready

## Configuration Files

- `.yamllint.yml` - YAML linting rules
- `.github/dependabot.yml` - Dependency update configuration
- `.github/workflows/*.yml` - Individual workflow definitions

## Quick Start

### Test Locally Before Pushing

```bash
# Python linting
black *.py
isort *.py
flake8 *.py
bandit -r *.py

# Shell scripts
shellcheck *.sh

# SQL files
sqlfluff lint *.sql

# Helm chart
helm lint chart/
helm template test chart/ --debug --dry-run

# Docker build
docker build -t collector:test ./collector
```

### Enable Workflows

Workflows are automatically enabled when merged to main. No additional configuration needed!

### Permissions

All workflows use the built-in `GITHUB_TOKEN` - no secret configuration required.

## Monitoring

- **Actions Tab**: View workflow runs and status
- **Security Tab**: View security scan results
- **Insights → Dependency Graph**: View dependencies and Dependabot alerts
- **Packages**: View published containers and charts

## Next Steps

1. ✅ Merge these workflows to main branch
2. ✅ Enable branch protection on main
3. ✅ Review and merge first Dependabot PRs
4. ✅ Test release process with a pre-release tag
5. ✅ Monitor security scan results weekly

## Support

For workflow issues:

- Check workflow logs in Actions tab
- Review `.github/workflows/README.md` for detailed documentation
- Test workflows manually using "Run workflow" button
