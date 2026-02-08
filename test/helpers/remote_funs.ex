defmodule Fusion.Test.Helpers.RemoteFuns do
  @moduledoc "Compiled helper module for run_fun tests against remote nodes."

  def hello, do: "hello from remote"

  def get_self, do: self()

  def make_spot(port), do: %Fusion.Net.Spot{host: "test", port: port}
end
