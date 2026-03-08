defmodule Fusion.Utilities.Bash do
  @moduledoc "Shell escaping utilities."

  @doc ~S"""
  Escapes a string for use inside double-quoted shell strings.

  Escapes backslashes, double quotes, dollar signs, and backticks.

  ## Examples

      iex> Fusion.Utilities.Bash.escape_str(~s(echo "$response"))
      ~s(echo \\"\\$response\\")

      iex> Fusion.Utilities.Bash.escape_str(~s(a\\b`c`))
      ~s(a\\\\b\\`c\\`)
  """
  def escape_str(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end
end
