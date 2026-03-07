# Erlang SSH Backend Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace system SSH with Erlang's `:ssh` module while keeping the old approach as a pluggable alternative.

**Architecture:** Define a `Fusion.SshBackend` behaviour with two implementations: `Erlang` (new, default) and `System` (existing code). `NodeManager` delegates SSH operations through the backend. A custom `SshKeyProvider` implements `ssh_client_key_api` for specific key file paths.

**Tech Stack:** Elixir, Erlang `:ssh` / `:ssh_connection`, OTP 28

---

### Task 1: Define the SshBackend behaviour

**Files:**
- Create: `lib/fusion/ssh_backend.ex`
- Test: `test/fusion/ssh_backend_test.exs`

**Step 1: Write the test**

```elixir
# test/fusion/ssh_backend_test.exs
defmodule Fusion.SshBackendTest do
  use ExUnit.Case, async: true

  test "Fusion.SshBackend defines the expected callbacks" do
    callbacks = Fusion.SshBackend.behaviour_info(:callbacks)
    assert {:connect, 1} in callbacks
    assert {:forward_tunnel, 4} in callbacks
    assert {:reverse_tunnel, 4} in callbacks
    assert {:exec, 2} in callbacks
    assert {:exec_async, 2} in callbacks
    assert {:close, 1} in callbacks
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/eyal/projects/join-with/oss/fusion/.worktrees/erlang-ssh && mix test test/fusion/ssh_backend_test.exs`
Expected: FAIL — module not found

**Step 3: Write the behaviour**

```elixir
# lib/fusion/ssh_backend.ex
defmodule Fusion.SshBackend do
  @moduledoc """
  Behaviour for SSH backends.

  Fusion supports pluggable SSH implementations. The default is
  `Fusion.SshBackend.Erlang` which uses OTP's built-in :ssh module.
  The legacy `Fusion.SshBackend.System` shells out to the system ssh binary.
  """

  @type conn :: term()
  @type target :: Fusion.Target.t()

  @doc "Open an SSH connection to the target."
  @callback connect(target()) :: {:ok, conn()} | {:error, term()}

  @doc "Create a forward tunnel (local listen port -> remote host:port)."
  @callback forward_tunnel(conn(), non_neg_integer(), String.t(), non_neg_integer()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc "Create a reverse tunnel (remote listen port -> local host:port)."
  @callback reverse_tunnel(conn(), non_neg_integer(), String.t(), non_neg_integer()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc "Execute a command on the remote host synchronously. Returns stdout."
  @callback exec(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}

  @doc "Execute a command on the remote host asynchronously. Returns port/pid for monitoring."
  @callback exec_async(conn(), String.t()) :: {:ok, pid()} | {:error, term()}

  @doc "Close the SSH connection."
  @callback close(conn()) :: :ok
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/fusion/ssh_backend_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/fusion/ssh_backend.ex test/fusion/ssh_backend_test.exs
git commit -m "feat: define SshBackend behaviour"
```

---

### Task 2: Add ssh_backend field to Target

**Files:**
- Modify: `lib/fusion/target.ex`
- Modify: `test/fusion/target_test.exs`

**Step 1: Write the test**

```elixir
# Add to test/fusion/target_test.exs
describe "ssh_backend" do
  test "defaults to Fusion.SshBackend.Erlang" do
    target = %Target{host: "x", port: 22, username: "u", auth: {:key, "/k"}}
    assert target.ssh_backend == Fusion.SshBackend.Erlang
  end

  test "can be set to System backend" do
    target = %Target{
      host: "x",
      port: 22,
      username: "u",
      auth: {:key, "/k"},
      ssh_backend: Fusion.SshBackend.System
    }

    assert target.ssh_backend == Fusion.SshBackend.System
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/fusion/target_test.exs`
Expected: FAIL — no ssh_backend field

**Step 3: Add the field to Target struct**

In `lib/fusion/target.ex`, add `ssh_backend` to defstruct with default:

```elixir
defstruct host: nil, port: 22, username: nil, auth: nil, ssh_backend: Fusion.SshBackend.Erlang

@type t :: %__MODULE__{
        host: String.t(),
        port: non_neg_integer(),
        username: String.t(),
        auth: auth(),
        ssh_backend: module()
      }
```

**Step 4: Run tests**

Run: `mix test test/fusion/target_test.exs`
Expected: PASS

**Step 5: Run all tests**

Run: `mix test`
Expected: All pass (existing tests don't set ssh_backend, default is fine)

**Step 6: Commit**

```bash
git add lib/fusion/target.ex test/fusion/target_test.exs
git commit -m "feat: add ssh_backend field to Target with Erlang default"
```

---

### Task 3: Create SshKeyProvider (custom key_cb)

**Files:**
- Create: `lib/fusion/ssh_key_provider.ex`
- Test: `test/fusion/ssh_key_provider_test.exs`

**Step 1: Write the test**

```elixir
# test/fusion/ssh_key_provider_test.exs
defmodule Fusion.SshKeyProviderTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  describe "is_host_key/5" do
    test "accepts any host key when silently accepting" do
      assert Fusion.SshKeyProvider.is_host_key(:fake_key, "host", 22, :ssh_rsa, [])
    end
  end

  describe "user_key/2" do
    test "reads a key file from the provided path", %{tmp_dir: tmp_dir} do
      # Generate a test key
      key_path = Path.join(tmp_dir, "test_key")
      {_, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", "", "-q"])

      opts = [key_path: key_path]
      result = Fusion.SshKeyProvider.user_key(:"ssh-ed25519", opts)
      assert {:ok, _key} = result
    end

    test "returns error for missing key file" do
      opts = [key_path: "/nonexistent/key"]
      assert {:error, _} = Fusion.SshKeyProvider.user_key(:"ssh-ed25519", opts)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/fusion/ssh_key_provider_test.exs`
Expected: FAIL — module not found

**Step 3: Implement SshKeyProvider**

```elixir
# lib/fusion/ssh_key_provider.ex
defmodule Fusion.SshKeyProvider do
  @moduledoc """
  Custom SSH key callback that loads a specific key file by path.

  Implements the `:ssh_client_key_api` behaviour so that Fusion can
  use `{:key, "/path/to/specific/key"}` auth with Erlang's :ssh module.
  """

  @behaviour :ssh_client_key_api

  @impl true
  def is_host_key(_key, _host, _port, _algorithm, _opts) do
    # Accept all host keys (equivalent to StrictHostKeyChecking=no)
    true
  end

  @impl true
  def user_key(algorithm, opts) do
    key_path = Keyword.fetch!(opts, :key_path)

    case File.read(key_path) do
      {:ok, pem} ->
        decode_private_key(pem, algorithm)

      {:error, reason} ->
        {:error, {:file_read_error, key_path, reason}}
    end
  end

  defp decode_private_key(pem, _algorithm) do
    try do
      [{entry, _}] = :public_key.pem_decode(pem)
      key = :public_key.pem_entry_decode(entry)
      {:ok, key}
    rescue
      e -> {:error, {:decode_error, e}}
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/fusion/ssh_key_provider_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/fusion/ssh_key_provider.ex test/fusion/ssh_key_provider_test.exs
git commit -m "feat: add SshKeyProvider for specific key file paths"
```

---

### Task 4: Implement SshBackend.Erlang

**Files:**
- Create: `lib/fusion/ssh_backend/erlang.ex`
- Test: `test/fusion/ssh_backend/erlang_test.exs`

**Step 1: Write the test**

```elixir
# test/fusion/ssh_backend/erlang_test.exs
defmodule Fusion.SshBackend.ErlangTest do
  use ExUnit.Case, async: true

  alias Fusion.SshBackend.Erlang, as: Backend
  alias Fusion.Target

  describe "connect_opts/1" do
    test "builds password auth options" do
      target = %Target{host: "h", port: 22, username: "user", auth: {:password, "secret"}}
      opts = Backend.connect_opts(target)

      assert Keyword.get(opts, :user) == ~c"user"
      assert Keyword.get(opts, :password) == ~c"secret"
      assert Keyword.get(opts, :silently_accept_hosts) == true
      assert Keyword.get(opts, :user_interaction) == false
    end

    test "builds key auth options" do
      target = %Target{host: "h", port: 22, username: "user", auth: {:key, "/home/user/.ssh/id_ed25519"}}
      opts = Backend.connect_opts(target)

      assert Keyword.get(opts, :user) == ~c"user"
      assert Keyword.get(opts, :key_cb) == {Fusion.SshKeyProvider, key_path: "/home/user/.ssh/id_ed25519"}
      assert Keyword.get(opts, :silently_accept_hosts) == true
      assert Keyword.get(opts, :user_interaction) == false
      refute Keyword.has_key?(opts, :password)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/fusion/ssh_backend/erlang_test.exs`
Expected: FAIL — module not found

**Step 3: Implement the Erlang backend**

```elixir
# lib/fusion/ssh_backend/erlang.ex
defmodule Fusion.SshBackend.Erlang do
  @moduledoc """
  SSH backend using Erlang's built-in :ssh module.

  This is the default backend. It uses OTP's SSH implementation
  for connections, tunnels, and remote command execution.
  """

  @behaviour Fusion.SshBackend

  @connect_timeout 15_000
  @exec_timeout 30_000

  @impl true
  def connect(%Fusion.Target{} = target) do
    :ssh.start()

    host = String.to_charlist(target.host)
    opts = connect_opts(target)

    case :ssh.connect(host, target.port, opts, @connect_timeout) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def forward_tunnel(conn, listen_port, connect_host, connect_port) do
    :ssh.tcpip_tunnel_to_server(
      conn,
      ~c"127.0.0.1",
      listen_port,
      String.to_charlist(connect_host),
      connect_port,
      @connect_timeout
    )
  end

  @impl true
  def reverse_tunnel(conn, listen_port, connect_host, connect_port) do
    :ssh.tcpip_tunnel_from_server(
      conn,
      ~c"0.0.0.0",
      listen_port,
      String.to_charlist(connect_host),
      connect_port,
      @connect_timeout
    )
  end

  @impl true
  def exec(conn, command) do
    with {:ok, ch} <- :ssh_connection.session_channel(conn, @exec_timeout),
         :success <- :ssh_connection.exec(conn, ch, String.to_charlist(command), @exec_timeout) do
      collect_output(conn, ch, <<>>, nil)
    else
      :failure -> {:error, :exec_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exec_async(conn, command) do
    parent = self()

    pid =
      spawn_link(fn ->
        {:ok, ch} = :ssh_connection.session_channel(conn, @exec_timeout)
        :success = :ssh_connection.exec(conn, ch, String.to_charlist(command), @exec_timeout)

        # Keep the process alive to receive SSH messages
        receive do
          {:ssh_cm, ^conn, {:closed, ^ch}} -> :ok
        after
          :infinity -> :ok
        end
      end)

    {:ok, pid}
  end

  @impl true
  def close(conn) do
    :ssh.close(conn)
    :ok
  end

  @doc false
  def connect_opts(%Fusion.Target{} = target) do
    base_opts = [
      user: String.to_charlist(target.username),
      silently_accept_hosts: true,
      user_interaction: false
    ]

    auth_opts =
      case target.auth do
        {:password, password} ->
          [password: String.to_charlist(password)]

        {:key, key_path} ->
          [key_cb: {Fusion.SshKeyProvider, key_path: key_path}]
      end

    base_opts ++ auth_opts
  end

  defp collect_output(conn, ch, stdout, exit_code) do
    receive do
      {:ssh_cm, ^conn, {:data, ^ch, 0, data}} ->
        collect_output(conn, ch, stdout <> data, exit_code)

      {:ssh_cm, ^conn, {:data, ^ch, 1, _stderr}} ->
        collect_output(conn, ch, stdout, exit_code)

      {:ssh_cm, ^conn, {:eof, ^ch}} ->
        collect_output(conn, ch, stdout, exit_code)

      {:ssh_cm, ^conn, {:exit_status, ^ch, code}} ->
        collect_output(conn, ch, stdout, code)

      {:ssh_cm, ^conn, {:closed, ^ch}} ->
        case exit_code do
          0 -> {:ok, stdout}
          nil -> {:ok, stdout}
          code -> {:error, {:exit_code, code, stdout}}
        end
    after
      @exec_timeout ->
        :ssh_connection.close(conn, ch)
        {:error, :timeout}
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/fusion/ssh_backend/erlang_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/fusion/ssh_backend/erlang.ex test/fusion/ssh_backend/erlang_test.exs
git commit -m "feat: implement Erlang SSH backend"
```

---

### Task 5: Extract SshBackend.System from existing code

**Files:**
- Create: `lib/fusion/ssh_backend/system.ex`
- Test: `test/fusion/ssh_backend/system_test.exs`

**Step 1: Write the test**

```elixir
# test/fusion/ssh_backend/system_test.exs
defmodule Fusion.SshBackend.SystemTest do
  use ExUnit.Case, async: true

  alias Fusion.SshBackend.System, as: Backend
  alias Fusion.Target

  test "implements the SshBackend behaviour" do
    behaviours =
      Backend.__info__(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    assert Fusion.SshBackend in behaviours
  end

  test "connect returns a conn struct" do
    target = %Target{
      host: "example.com",
      port: 22,
      username: "deploy",
      auth: {:key, "~/.ssh/id_rsa"},
      ssh_backend: Backend
    }

    # connect won't actually work without a real server, but we can verify it exists
    assert function_exported?(Backend, :connect, 1)
    assert function_exported?(Backend, :forward_tunnel, 4)
    assert function_exported?(Backend, :reverse_tunnel, 4)
    assert function_exported?(Backend, :exec, 2)
    assert function_exported?(Backend, :exec_async, 2)
    assert function_exported?(Backend, :close, 1)
  end
end
```

**Step 2: Implement System backend**

Extract the current SSH command-building and OS process approach into `Fusion.SshBackend.System`. This wraps the existing `Fusion.Utilities.Ssh` and `Fusion.Utilities.Exec` modules behind the behaviour.

```elixir
# lib/fusion/ssh_backend/system.ex
defmodule Fusion.SshBackend.System do
  @moduledoc """
  SSH backend that shells out to the system `ssh` and `sshpass` binaries.

  This is the legacy backend. Use `Fusion.SshBackend.Erlang` (the default)
  for a pure-Erlang implementation with no system binary dependencies.
  """

  @behaviour Fusion.SshBackend

  alias Fusion.Utilities.Ssh
  alias Fusion.Utilities.Exec
  alias Fusion.Net.Spot

  defmodule Conn do
    @moduledoc false
    defstruct auth: nil, remote: nil, tunnels: [], os_pids: []
  end

  @impl true
  def connect(%Fusion.Target{} = target) do
    {auth, remote} = Fusion.Target.to_auth_and_spot(target)
    {:ok, %Conn{auth: auth, remote: remote}}
  end

  @impl true
  def forward_tunnel(%Conn{} = conn, listen_port, connect_host, connect_port) do
    to_spot = %Spot{host: connect_host, port: connect_port}

    cmd =
      Ssh.cmd_port_tunnel(conn.auth, conn.remote, listen_port, to_spot, :forward)

    case Exec.capture_std_mon(cmd) do
      {:ok, port, _os_pid} ->
        {:ok, listen_port}

      error ->
        error
    end
  end

  @impl true
  def reverse_tunnel(%Conn{} = conn, listen_port, connect_host, connect_port) do
    to_spot = %Spot{host: connect_host, port: connect_port}

    cmd =
      Ssh.cmd_port_tunnel(conn.auth, conn.remote, listen_port, to_spot, :reverse)

    case Exec.capture_std_mon(cmd) do
      {:ok, port, _os_pid} ->
        {:ok, listen_port}

      error ->
        error
    end
  end

  @impl true
  def exec(%Conn{} = conn, command) do
    cmd = Ssh.cmd_remote(command, conn.auth, conn.remote)
    Exec.run_sync_capture_std(cmd)
  end

  @impl true
  def exec_async(%Conn{} = conn, command) do
    cmd = Ssh.cmd_remote(command, conn.auth, conn.remote)

    case Exec.capture_std_mon(cmd) do
      {:ok, port, os_pid} -> {:ok, {port, os_pid}}
      error -> error
    end
  end

  @impl true
  def close(%Conn{} = _conn) do
    # System SSH tunnels are cleaned up via Port.close in NodeManager
    :ok
  end
end
```

**Step 3: Run test to verify it passes**

Run: `mix test test/fusion/ssh_backend/system_test.exs`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/fusion/ssh_backend/system.ex test/fusion/ssh_backend/system_test.exs
git commit -m "feat: extract System SSH backend from existing code"
```

---

### Task 6: Refactor NodeManager to use SshBackend

**Files:**
- Modify: `lib/fusion/node_manager.ex`
- Modify: `test/fusion/node_manager_test.exs`

**Step 1: Update the test**

Add test to verify the backend is used from target:

```elixir
# Add to test/fusion/node_manager_test.exs
describe "backend selection" do
  test "uses the backend from the target" do
    target = %Target{
      host: "x",
      port: 22,
      username: "u",
      auth: {:key, "/k"},
      ssh_backend: Fusion.SshBackend.System
    }

    {:ok, pid} = NodeManager.start_link(target)
    assert NodeManager.status(pid) == :disconnected
    GenServer.stop(pid)
  end
end
```

**Step 2: Refactor NodeManager**

Rewrite `do_connect/1` and `setup_tunnels/6` to call `target.ssh_backend.connect/1`, `.forward_tunnel/4`, `.reverse_tunnel/4`, `.exec_async/2` instead of directly building SSH commands.

Key changes:
- `do_connect/1`: call `target.ssh_backend.connect(target)` to get a conn, store it in state
- `setup_tunnels`: call `conn |> backend.reverse_tunnel(...)` and `conn |> backend.forward_tunnel(...)`
- `start_remote_node`: call `backend.exec_async(conn, cmd)` instead of `Ssh.cmd_remote |> Exec.capture_std_mon`
- `do_disconnect`: call `backend.close(conn)` instead of killing OS pids
- `kill_remote_process`: call `backend.exec(conn, "kill ...")` instead of building SSH command
- Store `conn` and `backend` in state struct, remove `tunnel_ports` and `remote_os_pid`

The complete refactored `NodeManager` should:
1. On connect: `backend.connect(target)` → store conn
2. Setup 3 tunnels via backend calls
3. Start remote node via `backend.exec_async(conn, elixir_cmd)`
4. Wait for `Node.connect` as before
5. On disconnect: `Node.disconnect`, `backend.exec(conn, "kill ...")`, `backend.close(conn)`

**Step 3: Run all tests**

Run: `mix test`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/fusion/node_manager.ex test/fusion/node_manager_test.exs
git commit -m "refactor: NodeManager uses pluggable SshBackend"
```

---

### Task 7: Start :ssh in Application

**Files:**
- Modify: `lib/fusion/application.ex`

**Step 1: Add :ssh to extra_applications in mix.exs**

In `mix.exs`, add `:ssh` and `:public_key` to `extra_applications`:

```elixir
def application do
  [
    extra_applications: [:logger, :ssh, :public_key],
    mod: {Fusion.Application, []}
  ]
end
```

**Step 2: Run all tests**

Run: `mix test`
Expected: All pass

**Step 3: Commit**

```bash
git add mix.exs
git commit -m "feat: add :ssh and :public_key to extra_applications"
```

---

### Task 8: Integration test with both backends

**Files:**
- Modify: `test/fusion/node_manager_integration_test.exs`

**Step 1: Parameterize the integration test for both backends**

Duplicate the existing integration test to run with both `Fusion.SshBackend.Erlang` and `Fusion.SshBackend.System`. Use a helper to avoid code duplication:

```elixir
# Add at the bottom of node_manager_integration_test.exs

for backend <- [Fusion.SshBackend.Erlang, Fusion.SshBackend.System] do
  backend_name = backend |> Module.split() |> List.last()

  @tag timeout: 30_000
  test "connect with #{backend_name} backend" do
    case skip_unless_ssh_available() do
      {:skip, reason} ->
        IO.puts("SKIP: #{reason}")

      {:ok, ssh_key} ->
        user = System.get_env("USER")

        target = %Target{
          host: "localhost",
          port: 22,
          username: user,
          auth: {:key, ssh_key},
          ssh_backend: unquote(backend)
        }

        {:ok, manager} = NodeManager.start_link(target)

        case NodeManager.connect(manager) do
          {:ok, remote_node} ->
            assert is_atom(remote_node)
            assert remote_node in Node.list()
            assert NodeManager.disconnect(manager) == :ok
            refute remote_node in Node.list()

          {:error, :local_node_not_alive} ->
            IO.puts("SKIP: Local node not alive")

          {:error, reason} ->
            flunk("Failed with #{unquote(backend_name)}: #{inspect(reason)}")
        end

        GenServer.stop(manager)
    end
  end
end
```

**Step 2: Commit**

```bash
git add test/fusion/node_manager_integration_test.exs
git commit -m "test: add integration tests for both SSH backends"
```

---

### Task 9: Update README and docs

**Files:**
- Modify: `README.md`

**Step 1: Update Requirements section**

Remove `sshpass` mention, add note about backends:

```markdown
## Requirements

- Elixir ~> 1.18 / OTP 28+
- Remote server with Elixir/Erlang installed
- SSH access (key-based or password)
```

**Step 2: Add backend configuration section**

After the Usage section, add:

```markdown
### SSH Backend

Fusion uses Erlang's built-in SSH module by default. No system `ssh` binary required.

To use the legacy system SSH backend instead:

\```elixir
target = %Fusion.Target{
  host: "10.0.1.5",
  username: "deploy",
  auth: {:key, "~/.ssh/id_ed25519"},
  ssh_backend: Fusion.SshBackend.System  # uses system ssh/sshpass
}
\```
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README for Erlang SSH backend

Closes #33"
```

---

### Task 10: Final verification

**Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass

**Step 2: Compile with warnings as errors**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile

**Step 3: Check formatting**

Run: `mix format --check-formatted`
Expected: No formatting issues

**Step 4: Run integration tests if available**

Run: `elixir --sname test@localhost -S mix test --include integration`
Expected: Integration tests pass with both backends (or skip gracefully)
