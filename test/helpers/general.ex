defmodule Fusion.Test.Helpers.General do
  @moduledoc "General test helpers."

  def try_times(max_times, action) do
    try_times(max_times, action, max_times, 1000)
  end

  def try_times(_max_times, _action, 0, _sleep_time), do: :error_max_tries

  def try_times(max_times, action, count, sleep_time) do
    case action.() do
      {:ok, result} ->
        {:ok, result}

      :try_again ->
        Process.sleep(sleep_time)
        try_times(max_times, action, count - 1, sleep_time * 2)
    end
  end
end
