defmodule Fusion.SshKeyProviderTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  describe "is_host_key/5" do
    test "accepts any host key" do
      assert Fusion.SshKeyProvider.is_host_key(:fake_key, "host", 22, :ssh_rsa, [])
    end
  end

  describe "is_host_key/4" do
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
    @tag :tmp_dir
    test "reads an Ed25519 key file", %{tmp_dir: tmp_dir} do
      key_path = generate_key(tmp_dir, "test_key", "ed25519")
      assert {:ok, _key} = Fusion.SshKeyProvider.user_key(:"ssh-ed25519", key_path: key_path)
    end

    @tag :tmp_dir
    test "reads an RSA key file", %{tmp_dir: tmp_dir} do
      key_path = generate_key(tmp_dir, "test_rsa_key", "rsa", ["-b", "2048"])
      assert {:ok, _key} = Fusion.SshKeyProvider.user_key(:"ssh-rsa", key_path: key_path)
    end

    @tag :tmp_dir
    test "reads an ECDSA key file", %{tmp_dir: tmp_dir} do
      key_path = generate_key(tmp_dir, "test_ecdsa_key", "ecdsa", ["-b", "256"])

      assert {:ok, _key} =
               Fusion.SshKeyProvider.user_key(:"ecdsa-sha2-nistp256", key_path: key_path)
    end

    test "returns error for missing key file" do
      assert {:error, {:file_read_error, "/nonexistent/key", :enoent}} =
               Fusion.SshKeyProvider.user_key(:"ssh-ed25519", key_path: "/nonexistent/key")
    end

    test "raises KeyError when key_path option is missing" do
      assert_raise KeyError, fn ->
        Fusion.SshKeyProvider.user_key(:"ssh-ed25519", [])
      end
    end

    @tag :tmp_dir
    test "returns error for garbage data", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "bad_key")
      File.write!(key_path, "this is not a key")

      assert {:error, :unsupported_key_format} =
               Fusion.SshKeyProvider.user_key(:"ssh-rsa", key_path: key_path)
    end

    @tag :tmp_dir
    test "returns error for encrypted key", %{tmp_dir: tmp_dir} do
      key_path = generate_key(tmp_dir, "encrypted_key", "ed25519", ["-N", "my_passphrase"])

      assert {:error, :encrypted_key} =
               Fusion.SshKeyProvider.user_key(:"ssh-ed25519", key_path: key_path)
    end

    @tag :tmp_dir
    test "returns error when key type does not match requested algorithm", %{tmp_dir: tmp_dir} do
      key_path = generate_key(tmp_dir, "mismatch_key", "ed25519")

      log =
        capture_log(fn ->
          assert {:error, :key_type_mismatch} =
                   Fusion.SshKeyProvider.user_key(:"ssh-rsa", key_path: key_path)
        end)

      assert log =~ "key type mismatch"
    end
  end

  ## Helpers

  defp generate_key(tmp_dir, name, type, extra_opts \\ []) do
    key_path = Path.join(tmp_dir, name)
    # Default: no passphrase, quiet mode
    base_opts = ["-t", type, "-f", key_path, "-q"]

    opts =
      if Enum.any?(extra_opts, &(&1 == "-N")),
        do: base_opts ++ extra_opts,
        else: base_opts ++ ["-N", ""] ++ extra_opts

    {_, 0} = System.cmd("ssh-keygen", opts)
    key_path
  end
end
