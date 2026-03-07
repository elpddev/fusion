# Replace System SSH with Erlang :ssh Module — Design

## Goal

Replace all usage of system `ssh`/`sshpass` binaries with Erlang's built-in `:ssh` module while preserving the old approach as a pluggable alternative.

## Architecture

### Pluggable SSH Backend

A behaviour that both backends implement:

```elixir
defmodule Fusion.SshBackend do
  @callback connect(target) :: {:ok, conn} | {:error, reason}
  @callback forward_tunnel(conn, listen_port, remote_host, remote_port) :: {:ok, port} | {:error, reason}
  @callback reverse_tunnel(conn, remote_port, local_host, local_port) :: {:ok, port} | {:error, reason}
  @callback exec(conn, command) :: {:ok, output} | {:error, reason}
  @callback close(conn) :: :ok
end
```

Two implementations:
- `Fusion.SshBackend.Erlang` — new, uses `:ssh` module (default)
- `Fusion.SshBackend.System` — current behavior, shells out to `ssh`/`sshpass`

Configurable via `Fusion.Target`:
```elixir
%Fusion.Target{
  host: "10.0.1.5",
  username: "deploy",
  auth: {:key, "~/.ssh/id_ed25519"},
  ssh_backend: Fusion.SshBackend.Erlang  # or Fusion.SshBackend.System
}
```

### Erlang SSH API Mapping

| Fusion Need | Erlang :ssh API |
|-------------|-----------------|
| Forward tunnel (`ssh -L`) | `:ssh.tcpip_tunnel_to_server/6` |
| Reverse tunnel (`ssh -R`) | `:ssh.tcpip_tunnel_from_server/6` |
| Remote command execution | `:ssh_connection.session_channel/2` + `:ssh_connection.exec/4` |
| Password auth | `:ssh.connect(host, port, user: ..., password: ...)` |
| Key auth | `:ssh.connect(host, port, key_cb: {Fusion.SshKeyProvider, ...})` |
| Disconnect detection | `Process.monitor(conn_pid)` |
| Cleanup | `:ssh.close(conn)` |

### Custom Key Provider

`Fusion.SshKeyProvider` — implements `ssh_client_key_api` behaviour to load a specific key file by path. Preserves the current `{:key, "/path/to/key"}` UX instead of scanning a directory.

### Module Changes

**New modules:**
- `Fusion.SshBackend` — behaviour definition
- `Fusion.SshBackend.Erlang` — new `:ssh` based implementation
- `Fusion.SshBackend.System` — extracted from current code
- `Fusion.SshKeyProvider` — custom `ssh_client_key_api` for specific key files

**Modified:**
- `Fusion.Target` — add `ssh_backend` field, default `Fusion.SshBackend.Erlang`
- `Fusion.NodeManager` — use backend behaviour instead of direct SSH calls
- `Fusion.Application` — ensure `:ssh` is started

**Preserved (moved into System backend):**
- `Fusion.Utilities.Ssh` — used by System backend
- `Fusion.Utilities.Exec` — used by System backend
- `Fusion.SshPortTunnel` — used by System backend
- `Fusion.Connector` — refactored to use backend

### Gotchas

- All strings to `:ssh` must be charlists (`~c"..."`)
- `silently_accept_hosts: true` required for non-interactive use
- `user_interaction: false` to prevent stdin blocking
- `:ssh` app must be started before use
- One `session_channel` per `exec` call
- Exec output arrives async via `{:ssh_cm, conn, {:data, ...}}` messages
- OTP 22+ required for high-level tunnel APIs (we're on OTP 28)

### Testing

- Existing unit tests should continue passing
- Docker integration tests validate actual SSH behavior
- Add unit tests for `SshBackend.Erlang` and `SshKeyProvider`
- Test both backends in integration tests
