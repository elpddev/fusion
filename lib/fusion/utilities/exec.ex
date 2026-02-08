defmodule Fusion.Utilities.Exec do
  @moduledoc "OS process execution using Elixir Port (replaces erlexec dependency)."

  @doc """
  Runs a command asynchronously, capturing stdout/stderr.
  Returns `{:ok, port, os_pid}` where port is the Elixir port.

  The calling process will receive messages:
  - `{port, {:data, data}}` for stdout output
  - `{port, {:exit_status, status}}` when the process exits
  """
  def capture_std_mon(cmd) do
    port =
      Port.open({:spawn, cmd}, [
        :binary,
        :exit_status,
        :stderr_to_stdout
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {:ok, port, os_pid}
  end

  @doc """
  Runs a command synchronously and captures output.
  Returns `{:ok, output}` or `{:error, {exit_code, output}}`.
  """
  def run_sync_capture_std(cmd) do
    case System.cmd("/bin/sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {code, output}}
    end
  end

  @doc """
  Runs a command synchronously, printing output to stdout.
  """
  def run_sync_printall(cmd) do
    System.cmd("/bin/sh", ["-c", cmd], into: IO.stream(:stdio, :line))
  end
end
