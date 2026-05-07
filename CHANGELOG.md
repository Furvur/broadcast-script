Changelog
=========

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project ships as a rolling release (Docker image tag `latest`) and does not
yet use version tags, so all entries live under `[Unreleased]`. When a tagged
release cadence begins, dated version sections will be promoted from this list.

## [Unreleased]

### Added
- Smoke test now runs against Ubuntu 24.04 and 26.04 by default, with a `--ubuntu VERSION` flag to filter to one and per-version pass/fail reporting in the summary.
- Vagrant-based end-to-end smoke test (`tests/smoke/test_multipass_smoke.sh`) that boots a disposable VM, runs the real installer, and verifies containers, HTTP endpoints, systemd, and cron.
- Auto-prune of unused Docker images after upgrade, gated by a stability check so a freshly broken image is not reaped.
- Auto-migration of installations from the legacy `broadcast` registry namespace to `send-broadcast`.
- Docker-based integration tests for backup and restore (`tests/integration/test_backup_restore.sh`).
- Version-compatibility checking in the backup/restore flow so a restore aborts when the on-disk schema is incompatible with the installed image.
- Database restore from backup (`./broadcast.sh restore`) with automatic post-restore Rails migration.
- Instant log streaming trigger watcher using `inotifywait` for the web UI's on-demand log viewer.
- `restart-jobs` trigger to restart only the job container without bouncing the whole stack.
- On-demand log streaming for the web UI.
- Active Record encryption key generation during install so encrypted fields work out of the box.
- `BROADCAST_MANAGED` environment variable so managed installations can be identified at runtime.

### Changed
- Copyright notice updated to 2024–2026.
- Upgrades now pin to specific image version tags rather than pulling `latest`, so a rollback path exists if a bad image ships.

### Fixed
- Replaced the removed `ntp` package with `chrony` in the installer so fresh installs succeed on Ubuntu 26.04.
- License API response is validated before being parsed with `jq`, surfacing a clearer error when the API returns non-JSON or an error body.
- Database migrations now run automatically after a restore so the app boots against the restored schema.
- Installer fails fast with a helpful error when `.domain` is missing instead of producing confusing downstream errors.
- `DOCKER_IMAGE` is exported during install and image pulls so ARM hosts pick up the correct registry path.
- Update script now re-execs itself after pulling new code so the rest of the run uses the updated logic instead of the stale in-memory copy.
