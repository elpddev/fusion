defmodule Fusion.Test.Helpers.General do

  def try_times(max_times, action) do
    try_times(max_times, action, max_times, 1000)
  end

  def try_times(_max_times, _action, count, _sleep_time) when count == 0 do
    :error_max_tries
  end

  def try_times(max_times, action, count, sleep_time) do
    IO.puts "***try times: #{max_times - count + 1}"

    case action.() do
      {:ok, result} -> {:ok, result}
      :try_again ->
        Process.sleep(sleep_time)
        try_times(max_times, action, count - 1, sleep_time * 2)
    end
  end
end
