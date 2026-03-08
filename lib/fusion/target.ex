defmodule Fusion.Target do
  @moduledoc "Represents an SSH connection target."

  @enforce_keys [:host, :username, :auth]
  defstruct [:host, :username, :auth, port: 22, ssh_backend: Fusion.SshBackend.Erlang]

  @type auth :: {:key, String.t()} | {:password, String.t()}

  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          username: String.t(),
          auth: auth(),
          ssh_backend: module()
        }

  defimpl Inspect do
    def inspect(%{auth: {:password, _}} = target, opts) do
      redacted = %{target | auth: {:password, "**REDACTED**"}}
      Inspect.Any.inspect(redacted, opts)
    end

    def inspect(target, opts) do
      Inspect.Any.inspect(target, opts)
    end
  end
end
