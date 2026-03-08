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

      assert {:error, :unsupported_key_format} =
               Fusion.SshKeyProvider.user_key(:"ssh-rsa", opts)
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

  describe "sign/3" do
    test "produces a valid Ed25519 signature", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "sign_ed25519")
      {_, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", "", "-q"])
      {:ok, key} = Fusion.SshKeyProvider.user_key(:"ssh-ed25519", key_path: key_path)

      data = "test data for signing"
      signature = Fusion.SshKeyProvider.sign(key, data, [])
      assert is_binary(signature)

      # Verify the signature is cryptographically valid.
      # OTP 28 may represent Ed25519 keys as ECPrivateKey with namedCurve.
      pub_key = extract_ed25519_pub(key)
      assert :public_key.verify(data, :none, signature, pub_key)
    end

    test "produces a valid RSA signature", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "sign_rsa")

      {_, 0} =
        System.cmd("ssh-keygen", ["-t", "rsa", "-b", "2048", "-f", key_path, "-N", "", "-q"])

      {:ok, key} = Fusion.SshKeyProvider.user_key(:"ssh-rsa", key_path: key_path)

      data = "test data for signing"
      signature = Fusion.SshKeyProvider.sign(key, data, [])
      assert is_binary(signature)

      pub_key = extract_rsa_pub(key)
      assert :public_key.verify(data, :sha256, signature, pub_key)
    end

    test "produces a valid ECDSA signature", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "sign_ecdsa")

      {_, 0} =
        System.cmd("ssh-keygen", [
          "-t",
          "ecdsa",
          "-b",
          "256",
          "-f",
          key_path,
          "-N",
          "",
          "-q"
        ])

      {:ok, key} = Fusion.SshKeyProvider.user_key(:"ecdsa-sha2-nistp256", key_path: key_path)

      data = "test data for signing"
      signature = Fusion.SshKeyProvider.sign(key, data, [])
      assert is_binary(signature)

      {pub_key, ec_params} = extract_ecdsa_pub(key)
      assert :public_key.verify(data, :sha256, signature, {pub_key, ec_params})
    end

    test "respects hash option from OTP negotiation", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "sign_rsa_opts")

      {_, 0} =
        System.cmd("ssh-keygen", ["-t", "rsa", "-b", "2048", "-f", key_path, "-N", "", "-q"])

      {:ok, key} = Fusion.SshKeyProvider.user_key(:"ssh-rsa", key_path: key_path)

      data = "test data for signing"
      # Pass hash: :sha512 to simulate rsa-sha2-512 negotiation
      signature = Fusion.SshKeyProvider.sign(key, data, hash: :sha512)
      assert is_binary(signature)

      pub_key = extract_rsa_pub(key)
      assert :public_key.verify(data, :sha512, signature, pub_key)
    end
  end

  describe "user_key/2 algorithm mismatch" do
    test "logs warning when key type does not match requested algorithm", %{tmp_dir: tmp_dir} do
      key_path = Path.join(tmp_dir, "mismatch_key")
      {_, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", "", "-q"])

      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:ok, _key} = Fusion.SshKeyProvider.user_key(:"ssh-rsa", key_path: key_path)
        end)

      assert log =~ "key type mismatch"
    end
  end

  ## Key extraction helpers — abstract OTP version differences

  # Ed25519 keys may be {:ed_pri, ...} or {:ECPrivateKey, ...} depending on OTP version.
  defp extract_ed25519_pub({:ed_pri, :ed25519, pub_bytes, _priv}),
    do: {:ed_pub, :ed25519, pub_bytes}

  defp extract_ed25519_pub({:ECPrivateKey, _, _priv, {:namedCurve, {1, 3, 101, 112}}, pub, _}),
    do: {:ed_pub, :ed25519, pub}

  defp extract_ed25519_pub(key),
    do: flunk("Unexpected Ed25519 key format: #{inspect(key)}")

  # RSA keys — extract modulus and public exponent for verification
  defp extract_rsa_pub(key) when is_tuple(key) and elem(key, 0) == :RSAPrivateKey do
    modulus = elem(key, 2)
    pub_exp = elem(key, 3)
    {:RSAPublicKey, modulus, pub_exp}
  end

  defp extract_rsa_pub(key),
    do: flunk("Unexpected RSA key format: #{inspect(key)}")

  # ECDSA keys — extract public point and curve params for verification
  defp extract_ecdsa_pub(key) when is_tuple(key) and elem(key, 0) == :ECPrivateKey do
    pub_point = elem(key, 4)
    curve_params = elem(key, 3)
    {{:ECPoint, pub_point}, curve_params}
  end

  defp extract_ecdsa_pub(key),
    do: flunk("Unexpected ECDSA key format: #{inspect(key)}")
end
