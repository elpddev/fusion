defmodule Fusion.Utilities.Exec do
  @moduledoc """
  """

  def capture_std_mon(cmd) do
    cmd
    |> String.to_char_list
    |> IO.inspect
    |> :exec.run([:stdout, :stderr, :monitor])
  end

  def run_sync_capture_std(cmd) do
    cmd
    |> String.to_char_list
    |> IO.inspect
    |> :exec.run([:sync, :stdout, :stderr])
  end

  def run_printall(cmd) do
    cmd
    |> String.to_char_list
    |> IO.inspect
    |> :exec.run([stdout: :print, stderr: :print])
  end

  def run_sync_printall(cmd) do
    cmd
    |> String.to_char_list
    |> IO.inspect
    |> :exec.run([:sync, stdout: :print, stderr: :print])
  end
end
