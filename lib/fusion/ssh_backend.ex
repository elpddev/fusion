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
