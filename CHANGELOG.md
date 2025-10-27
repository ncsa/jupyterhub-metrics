# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2025-10-27

### Added
- Added `department` and `job_title` columns to users table schema
- Created jupyterhub-demographics.json Grafana dashboard

### Fixed
- Removed unused placeholder secret when external secrets are enabled
- Corrected permissions for helm chart upload
- Use sha- prefix for docker tags to avoid invalid tags in releases

## [1.1.0] - 2025-10-26

### Added

- Use GitHub Container Registry for collector images.
- Add comprehensive GitHub Actions workflows for CI/CD.

### Changed

- Enforced code quality with Black, isort, Pylint, and mypy.

### Fixed

- Resolved various linting and type errors in Python scripts and shell scripts.
- Corrected file permissions on shell scripts.
- Fixed issues with the markdown linting configuration.

## [1.0.0] - 2025-10-26

### Initial Release

JupyterHub Metrics is a comprehensive monitoring system for tracking JupyterHub usage, resource consumption, and user demographics. This initial release provides complete infrastructure for collecting, storing, and visualizing JupyterHub pod metrics.

### Features

#### Core Infrastructure

- **TimescaleDB Backend**: Time-series database with hypertables for efficient metrics storage
- **Automated Data Collection**: Collector service that monitors JupyterHub pods every 5 minutes
- **Session Tracking**: Intelligent session detection and aggregation from container observations
- **User Demographics**: Integration with Microsoft Graph API for user department and job title data

#### Deployment Options

- **Helm Chart**: Production-ready Kubernetes deployment with ConfigMaps and PersistentVolumes
- **Docker Compose**: Local development environment for testing and development
- **Flexible Configuration**: Environment-based configuration supporting multiple deployments

#### Data Collection & Storage

- Container observation tracking (user, node, image, runtime)
- User session materialized views with automatic refresh
- Continuous aggregates for hourly node and image statistics
- GPU vs CPU usage differentiation based on node naming
- Indefinite data retention (no automatic deletion policies)

#### Grafana Dashboards

- **Overview Dashboard**: System-wide metrics and trends
- **User Detail Dashboard**: Individual user activity and resource consumption
- **Demographics Dashboard**: Department and job title breakdowns
- **User Timeline**: Historical user activity tracking
- Automatic dashboard provisioning via ConfigMaps
- Anonymous viewer access support

#### User Management

- Microsoft Graph API integration for user profile synchronization
- Incremental and full refresh modes for user data
- Department and job title tracking with special handling for Fellowships
- CSV export of user usage statistics

#### Developer Experience

- Comprehensive AGENTS.md guide for AI-assisted development
- Safety rules for database operations (no drops, no deletes)
- Git commit guidelines and conventions
- Python virtual environment with all required dependencies
- Database migration framework

### Technical Details

**Database Schema:**

- `users` table: User profile information
- `container_observations` hypertable: Raw time-series pod observations
- `user_sessions` materialized view: Computed user sessions
- `user_session_stats` view: Aggregated user statistics
- Continuous aggregates: `hourly_node_stats`, `hourly_image_stats`

**Deployment:**

- TimescaleDB (PostgreSQL 15 with TimescaleDB extension)
- Grafana with automated provisioning
- Kubernetes-aware collector using kubectl
- Support for multiple namespaces and contexts

**Export & Reporting:**

- User usage statistics export to CSV
- User details synchronization from Microsoft Graph
- Configurable collection intervals
- Test scripts for validation

### License

- MIT License with National Center for Supercomputing Applications (NCSA) copyright

---

[1.0.0]: https://github.com/ncsa/jupyterhub-metrics/releases/tag/v1.0.0
