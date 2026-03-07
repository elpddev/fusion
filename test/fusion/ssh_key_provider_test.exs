defmodule Fusion.SshKeyProviderTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  describe "is_host_key/5" do
    test "accepts any host key when silently accepting" do
      assert Fusion.SshKeyProvider.is_host_key(:fake_key, "host", 22, :ssh_rsa, [])
    end
  end

  describe "user_key/2" do
    test "reads a key file from the provided path", %{tmp_dir: tmp_dir} do
      # Generate a test key
      key_path = Path.join(tmp_dir, "test_key")
      {_, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", "", "-q"])

      opts = [key_path: key_path]
      result = Fusion.SshKeyProvider.user_key(:"ssh-ed25519", opts)
      assert {:ok, _key} = result
    end

    test "returns error for missing key file" do
      opts = [key_path: "/nonexistent/key"]
      assert {:error, _} = Fusion.SshKeyProvider.user_key(:"ssh-ed25519", opts)
    end
  end
end
