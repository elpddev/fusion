<p align="center">
<img width="614" height="409" alt="fusion" src="https://github.com/user-attachments/assets/d4cdbf66-658c-46d0-8f43-99941f18101d" />
</p>

# Fusion

Remote task runner using Erlang distribution over SSH. Zero dependencies.

Fusion connects to remote servers via SSH, sets up port tunnels for Erlang distribution, bootstraps a remote BEAM node, and lets you run Elixir code on it. Think Ansible/Chef but for Elixir - push modules and execute functions on remote machines without pre-installing your application.

[![Hex.pm](https://img.shields.io/hexpm/v/fusion.svg)](https://hex.pm/packages/fusion)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/fusion)

## Articles

- [Running Elixir on Remote Servers with Fusion](https://eyallapid.me/blog/running-elixir-on-remote-servers-with-fusion)
- [How Fusion Works: Tunnels and Distribution](https://eyallapid.me/blog/how-fusion-works-tunnels-and-distribution)
- [How Fusion Works: Bytecode Pushing](https://eyallapid.me/blog/how-fusion-works-bytecode-pushing)

## Requirements

- Elixir ~> 1.18 / OTP 28+
- Remote server with Elixir/Erlang installed
- SSH access (key-based or password via `sshpass`)

## Installation

Add `fusion` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fusion, "~> 0.2.0"}
  ]
end
```

## Usage

Your local BEAM must be started as a distributed node:

```bash
iex --sname myapp@localhost -S mix
```

Then connect and run code remotely:

```elixir
# Define the target
target = %Fusion.Target{
  host: "10.0.1.5",
  port: 22,
  username: "deploy",
  auth: {:key, "~/.ssh/id_ed25519"}
}

# Connect (sets up tunnels, bootstraps remote BEAM, joins cluster)
{:ok, manager} = Fusion.NodeManager.start_link(target)
{:ok, remote_node} = Fusion.NodeManager.connect(manager)
```

Run functions on the remote:

```elixir
# Get remote system info
{:ok, version} = Fusion.run(remote_node, System, :version, [])
{:ok, {hostname, 0}} = Fusion.run(remote_node, System, :cmd, ["hostname", []])
```

Run anonymous functions directly:

```elixir
{:ok, info} = Fusion.run_fun(remote_node, fn ->
  %{
    node: Node.self(),
    otp: System.otp_release(),
    os: :os.type()
  }
end)
```

Push and run your own modules — dependencies are resolved automatically:

```elixir
defmodule RemoteHealth do
  def check do
    %{
      hostname: hostname(),
      elixir_version: System.version(),
      memory_mb: memory_mb()
    }
  end

  defp hostname do
    {name, _} = System.cmd("hostname", [])
    String.trim(name)
  end

  defp memory_mb do
    {meminfo, _} = System.cmd("cat", ["/proc/meminfo"])

    meminfo
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "MemTotal"))
    |> String.split(~r/\s+/)
    |> Enum.at(1)
    |> String.to_integer()
    |> div(1024)
  end
end

{:ok, health} = Fusion.run(remote_node, RemoteHealth, :check, [])
# => %{hostname: "web-01", elixir_version: "1.18.4", memory_mb: 7982}
```

Disconnect when done:

```elixir
Fusion.NodeManager.disconnect(manager)
```

### Automatic Dependency Resolution

When you run `RemoteHealth` remotely, Fusion reads the BEAM bytecode, walks the dependency tree, and pushes everything the module needs. You don't need to manually track the dependency chain.

```elixir
# You can also push modules explicitly
Fusion.TaskRunner.push_module(remote_node, MyApp.Worker)
Fusion.TaskRunner.push_modules(remote_node, [MyApp.Config, MyApp.Utils])
```

Standard library modules (Kernel, Enum, String, etc.) are already on the remote and don't need pushing.

## How It Works

### 1. SSH Tunnel Setup

Fusion creates 3 SSH tunnels between local and remote:

```
Local Machine                         Remote Server
─────────────                         ─────────────
                 ┌─── Reverse ────┐
Local node port ◄┘   tunnel #1    └── Remote can reach local node

                 ┌─── Forward ────┐
localhost:port ──┘   tunnel #2    └►  Remote node's dist port

                 ┌─── Reverse ────┐
Local EPMD     ◄─┘   tunnel #3    └── Remote registers with local EPMD
(port 4369)
```

### 2. Remote BEAM Bootstrap

Starts Elixir on the remote via SSH with carefully configured flags:

- `ERL_EPMD_PORT=<tunneled>` - routes EPMD registration through tunnel #3 back to local EPMD
- `--sname worker@localhost` - uses `@localhost` because all traffic goes through localhost-bound tunnels
- `--cookie <local_cookie>` - matches the local cluster's cookie
- `--erl "-kernel inet_dist_listen_min/max <port>"` - pins distribution port to match tunnel #2

### 3. Transparent Connection

Since the remote registered with the *local* EPMD, `Node.connect/1` works as if the remote node were local. All distribution traffic is routed through the SSH tunnels.

### 4. Code Pushing

Module bytecode is transferred via Erlang distribution:
1. Read `.beam` binary locally with `:code.get_object_code/1`
2. Parse BEAM atoms table to find non-stdlib dependencies
3. Push each dependency recursively (bottom-up)
4. Load on remote with `:code.load_binary/3`
5. Execute via `:erpc.call/4`

## Testing

```bash
# Unit tests (no external dependencies)
mix test

# Docker integration tests (requires Docker)
cd test/docker && ./run.sh start
elixir --sname fusion_test@localhost -S mix test --include external

# Stop the test container
cd test/docker && ./run.sh stop
```

### Test Tiers

- **Tier 1 (Unit)** - Doctests and pure logic tests. No network, no SSH.
- **Tier 2 (Integration)** - Tests against localhost SSH. Skips gracefully if not configured.
- **Tier 3 (External)** - End-to-end tests against a Docker container with SSH + Elixir. Requires `./run.sh start`.

## Architecture

```
Fusion (public API)
├── TaskRunner        - Remote code execution + module pushing + dependency resolution
├── NodeManager       - GenServer: tunnel setup, BEAM bootstrap, connection lifecycle
├── Target            - SSH connection configuration struct
├── TunnelSupervisor  - DynamicSupervisor for tunnel processes
├── Net               - Port generation, EPMD utilities
├── Connector         - SSH connection GenServer
├── SshPortTunnel     - SSH port tunnel process wrapper
├── PortRelay         - Port relay process wrapper
├── UdpTunnel         - UDP tunnel process wrapper
└── Utilities
    ├── Ssh           - SSH command string generation
    ├── Exec          - OS process execution (Port/System.cmd)
    ├── Erl           - Erlang CLI command builder
    └── Bash/Socat/Netcat/Netstat/Telnet - CLI tool wrappers
```

## License

MIT
