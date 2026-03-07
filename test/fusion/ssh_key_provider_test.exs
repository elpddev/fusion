defmodule Fusion.SshKeyProviderTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  describe "is_host_key/5" do
    test "accepts any host key when silently accepting" do
      assert Fusion.SshKeyProvider.is_host_key(:fake_key, "host", 22, :ssh_rsa, [])
    end
  end

  describe "is_host_key/4 (4-arity)" do
    test "accepts any host key" do
      assert Fusion.SshKeyProvider.is_host_key(:fake_key, "host", :ssh_rsa, [])
    end
  end

  describe "add_host_key/4" do
    test "returns :ok" do
      assert :ok = Fusion.SshKeyProvider.add_host_key("host", 22, :fake_key, [])
    end
  end

  describe "add_host_key/3" do
    test "returns :ok" do
      assert :ok = Fusion.SshKeyProvider.add_host_key("host", :fake_key, [])
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

  describe "user_key/2 with invalid data" do
    test "returns error for garbage data", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "bad_key")
      File.write!(key_path, "this is not a key")
      opts = [key_path: key_path]
      assert {:error, :unsupported_key_format} = Fusion.SshKeyProvider.user_key(:"ssh-rsa", opts)
    end
  end

  describe "user_key/2 with RSA key" do
    test "reads an RSA key file", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "test_rsa_key")

      {_, 0} =
        System.cmd("ssh-keygen", ["-t", "rsa", "-b", "2048", "-f", key_path, "-N", "", "-q"])

      opts = [key_path: key_path]
      assert {:ok, _key} = Fusion.SshKeyProvider.user_key(:"ssh-rsa", opts)
    end
  end
end
