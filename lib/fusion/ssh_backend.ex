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

  @type exec_error ::
          {:exit_status, integer(), stdout :: String.t(), stderr :: String.t()}
          | :exec_failed
          | :timeout
          | :output_exceeded_limit

  @doc """
  Execute a command on the remote host synchronously. Returns stdout on success.

  Non-zero exits return `{:error, {:exit_status, code, stdout, stderr}}`.
  """
  @callback exec(conn(), String.t()) :: {:ok, String.t()} | {:error, exec_error()}

  @doc """
  Execute a command on the remote host asynchronously (fire-and-forget).

  Returns `{:ok, pid}` where `pid` is the process handling the async command.
  The caller should not monitor or interact with this pid — it exists only to
  confirm the command was launched. Output and exit status are discarded.
  Use `exec/2` if you need results.
  """
  @callback exec_async(conn(), String.t()) :: {:ok, pid()} | {:error, term()}

  @doc "Close the SSH connection."
  @callback close(conn()) :: :ok
end
