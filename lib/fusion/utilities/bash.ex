defmodule Fusion.Utilities.Bash do
  @moduledoc "Shell escaping utilities."

  @doc ~S"""
  Escapes a string for use inside double-quoted shell strings.

  ## Examples

      iex> Fusion.Utilities.Bash.escape_str(~s(echo "$response"))
      ~s(echo \\"\\$response\\")
  """
  def escape_str(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
  end
end
