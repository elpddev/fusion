defmodule Fusion.Target do
  @moduledoc "Represents an SSH connection target."

  defstruct host: nil, port: 22, username: nil, auth: nil

  @type auth :: {:key, String.t()} | {:password, String.t()}

  @type t :: %__MODULE__{
          host: String.t(),
          port: non_neg_integer(),
          username: String.t(),
          auth: auth()
        }

  @doc """
  Converts a Target into the legacy auth/remote format used by tunnel modules.

  Returns `{auth_map, %Fusion.Net.Spot{}}`.
  """
  def to_auth_and_spot(%__MODULE__{} = target) do
    auth =
      case target.auth do
        {:key, path} -> %{username: target.username, key_path: path}
        {:password, pass} -> %{username: target.username, password: pass}
      end

    remote = %Fusion.Net.Spot{host: target.host, port: target.port}
    {auth, remote}
  end
end
