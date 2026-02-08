defmodule Fusion.Net.Spot do
  @moduledoc "Represents a network endpoint (host + port)."

  defstruct host: nil, port: nil

  @type t :: %__MODULE__{
          host: String.t() | nil,
          port: non_neg_integer() | nil
        }
end
