defmodule Fusion.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Fusion.TunnelSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Fusion.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
