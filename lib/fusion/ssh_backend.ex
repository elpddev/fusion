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

  @doc """
  Execute a command on the remote host synchronously. Returns stdout on success.

  Error shapes may vary by backend (e.g., `{:error, {:exit_code, code, stdout, stderr}}`
  for the Erlang backend). Callers should match on `{:error, _}` generically.
  """
  @callback exec(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Execute a command on the remote host asynchronously (fire-and-forget).

  Returns `{:ok, ref}` where `ref` is an opaque reference. The caller should not
  monitor or interact with this reference — it exists only to confirm the command
  was launched. Output and exit status are discarded. Use `exec/2` if you need results.
  """
  @callback exec_async(conn(), String.t()) :: {:ok, term()} | {:error, term()}

  @doc "Close the SSH connection."
  @callback close(conn()) :: :ok
end
