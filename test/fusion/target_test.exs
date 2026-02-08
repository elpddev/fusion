defmodule Fusion.TargetTest do
  use ExUnit.Case, async: true

  alias Fusion.Target
  alias Fusion.Net.Spot

  describe "to_auth_and_spot/1" do
    test "converts key-based target" do
      target = %Target{
        host: "10.0.1.5",
        port: 22,
        username: "deploy",
        auth: {:key, "~/.ssh/id_rsa"}
      }

      {auth, remote} = Target.to_auth_and_spot(target)

      assert auth == %{username: "deploy", key_path: "~/.ssh/id_rsa"}
      assert remote == %Spot{host: "10.0.1.5", port: 22}
    end

    test "converts password-based target" do
      target = %Target{
        host: "example.com",
        port: 2222,
        username: "admin",
        auth: {:password, "secret"}
      }

      {auth, remote} = Target.to_auth_and_spot(target)

      assert auth == %{username: "admin", password: "secret"}
      assert remote == %Spot{host: "example.com", port: 2222}
    end
  end
end
