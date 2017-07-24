defmodule Fusion.Net do
  @doc """
  """
  def gen_port(start_range \\ 49152, end_range \\ 65635) do
    range = end_range - start_range
    start_range + :rand.uniform(range)
  end
end
