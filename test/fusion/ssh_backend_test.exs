defmodule Fusion.SshBackendTest do
  use ExUnit.Case, async: true

  test "Fusion.SshBackend defines the expected callbacks" do
    callbacks = Fusion.SshBackend.behaviour_info(:callbacks)
    assert {:connect, 1} in callbacks
    assert {:forward_tunnel, 4} in callbacks
    assert {:reverse_tunnel, 4} in callbacks
    assert {:exec, 2} in callbacks
    assert {:exec_async, 2} in callbacks
    assert {:close, 1} in callbacks
  end
end
