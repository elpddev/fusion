# Changelog

## 0.3.0

- **Erlang SSH backend** — Fusion now uses OTP's built-in `:ssh` module by default instead of shelling out to the system `ssh` binary. No external SSH binary required.
- Pluggable `SshBackend` behaviour for swapping SSH implementations
- `SshKeyProvider` for loading specific key file paths with Erlang SSH
- Legacy system SSH backend available as `Fusion.SshBackend.System`
- Improved tunnel cleanup using clean SSH disconnect instead of SIGKILL
- Tunnel setup retry with `:not_accepted` handling for robustness
- CI: external SSH tests with Docker container
- Comprehensive external test coverage for both SSH backends

## 0.2.0

- First hex.pm release
- Remote task runner with automatic code pushing and dependency resolution
- SSH tunnel setup for Erlang distribution
- Remote BEAM node bootstrap and lifecycle management
- ERL boot server analyzer

## 0.1.0

- Initial release (GitHub only)
