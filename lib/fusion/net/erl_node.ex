defmodule Fusion.Net.ErlNode do
  @moduledoc "Represents an Erlang node's connection information."

  defstruct name: nil, host: nil, port: nil, cookie: nil

  @type t :: %__MODULE__{
          name: String.t() | nil,
          host: String.t() | nil,
          port: non_neg_integer() | nil,
          cookie: atom() | String.t() | nil
        }
end
