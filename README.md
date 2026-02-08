# Fusion

Remote task runner using Erlang distribution over SSH. Zero dependencies.

Fusion connects to remote servers via SSH, sets up port tunnels for Erlang distribution, bootstraps a remote BEAM node, and lets you run Elixir code on it. Think Ansible/Chef but for Elixir - push modules and execute functions on remote machines without pre-installing your application.

## Requirements

- Elixir ~> 1.18 / OTP 28+
- Remote server with Elixir/Erlang installed
- SSH access (key-based or password via `sshpass`)

## Installation

Add `fusion` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fusion, github: "elpddev/fusion"}
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

# Run code remotely (MFA form)
{:ok, 3} = Fusion.run(remote_node, Kernel, :+, [1, 2])

# Run system commands on the remote
{:ok, {hostname, 0}} = Fusion.run(remote_node, System, :cmd, ["hostname", []])

# Push and run your own modules (dependencies are resolved automatically)
{:ok, result} = Fusion.run(remote_node, MyApp.Worker, :process, [data])

# Disconnect and clean up
Fusion.NodeManager.disconnect(manager)
```

### Automatic Dependency Resolution

When you run `MyApp.Worker` remotely, Fusion automatically pushes all project modules that `Worker` references (struct usage, function calls, etc.). You don't need to manually track the dependency chain.

```elixir
# This pushes MyApp.Worker AND any project modules it depends on
{:ok, result} = Fusion.run(remote_node, MyApp.Worker, :do_work, [])

# You can also push explicitly
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
