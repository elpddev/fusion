defmodule Fusion.Utilities.Bash do

  @doc """

  ## Examples
  
  iex> escape_str("echo \\"$response\\"")
  "echo \\\\\\"\\\\$response\\\\\\""
  """
  def escape_str(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
  end

end
