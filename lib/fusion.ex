defmodule Fusion do
  @moduledoc """
  Remote task runner using Erlang distribution over SSH.

  Fusion connects to remote servers via SSH, sets up port tunnels for
  Erlang distribution (EPMD + node ports), bootstraps a remote BEAM node,
  and enables running Elixir code remotely.

  ## Quick Start

      target = %Fusion.Target{
        host: "10.0.1.5",
        port: 22,
        username: "deploy",
        auth: {:key, "~/.ssh/id_rsa"}
      }

      {:ok, manager} = Fusion.NodeManager.start_link(target)
      {:ok, remote_node} = Fusion.NodeManager.connect(manager)

      {:ok, result} = Fusion.run(remote_node, fn -> System.cmd("hostname", []) end)
      {:ok, 3} = Fusion.run(remote_node, Kernel, :+, [1, 2])
  """

  alias Fusion.TaskRunner

  @doc """
  Run an MFA (Module, Function, Args) on a remote node.

  The module's bytecode is automatically pushed to the remote node if needed.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  defdelegate run(node, module, function, args, opts \\ []), to: TaskRunner

  @doc """
  Run an anonymous function on a remote node.

  The module defining the function is automatically pushed to the remote node.

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  defdelegate run_fun(node, fun, opts \\ []), to: TaskRunner
end
