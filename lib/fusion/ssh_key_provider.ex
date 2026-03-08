defmodule Fusion.SshKeyProvider do
  @moduledoc """
  Custom SSH key callback that loads a specific key file by path.

  Implements the `:ssh_client_key_api` behaviour so that Fusion can
  use `{:key, "/path/to/specific/key"}` auth with Erlang's :ssh module.

  ## Security

  Host key verification is disabled — `is_host_key/4,5` always returns `true`.
  This is equivalent to `StrictHostKeyChecking=no` in OpenSSH.
  """

  @behaviour :ssh_client_key_api

  require Logger

  @impl true
  def is_host_key(_key, _host, _port, _algorithm, _opts) do
    # Accept all host keys (equivalent to StrictHostKeyChecking=no)
    true
  end

  @impl true
  def is_host_key(_key, _host, _algorithm, _opts) do
    true
  end

  @impl true
  def add_host_key(_host, _port, _key, _opts) do
    :ok
  end

  @impl true
  def add_host_key(_host, _key, _opts) do
    :ok
  end

  @impl true
  def user_key(algorithm, opts) do
    key_path = Keyword.fetch!(opts, :key_path)

    case File.read(key_path) do
      {:ok, pem} ->
        case decode_private_key(pem) do
          {:ok, key} ->
            expected = key_type_for_algorithm(algorithm)
            actual = key_type(key)

            if expected != nil and expected != actual do
              Logger.warning(
                "SSH key type mismatch: requested #{algorithm} but key at #{key_path} is #{actual}"
              )
            end

            {:ok, key}

          error ->
            error
        end

      {:error, reason} ->
        {:error, {:file_read_error, key_path, reason}}
    end
  end

  @impl true
  def sign(key, data, _opts) do
    hash = hash_for_key(key)
    :public_key.sign(data, hash, key)
  end

  defp hash_for_key(key) do
    case key do
      # Ed25519/Ed448 — EdDSA does its own hashing
      {:ed_pri, _, _, _} -> :none
      {:ed_pub, _, _} -> :none
      # OTP 28 may represent Ed25519 as ECPrivateKey with curve OID {1,3,101,112}
      {:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 112}}, _, _} -> :none
      # OTP 28 may represent Ed448 as ECPrivateKey with curve OID {1,3,101,113}
      {:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 113}}, _, _} -> :none
      # ECDSA (NIST curves)
      {:ECPrivateKey, _, _, _, _, _} -> :sha256
      # RSA — use sha256 for rsa-sha2-256 (modern default)
      _ -> :sha256
    end
  end

  defp decode_private_key(data) do
    # Try OpenSSH key v1 format first (modern ssh-keygen default),
    # then fall back to PEM format for older keys.
    with {:error, _} <- decode_openssh_key(data),
         {:error, _} <- decode_pem_key(data) do
      {:error, :unsupported_key_format}
    end
  end

  defp decode_openssh_key(data) do
    case :ssh_file.decode(data, :openssh_key_v1) do
      [{key, _attrs} | _] ->
        {:ok, key}

      _ ->
        {:error, :openssh_decode_failed}
    end
  rescue
    _ -> {:error, :openssh_decode_failed}
  catch
    _, _ -> {:error, :openssh_decode_failed}
  end

  defp key_type_for_algorithm(algorithm) do
    case algorithm do
      :"ssh-ed25519" -> :ed25519
      :"ssh-ed448" -> :ed448
      :"ssh-rsa" -> :rsa
      :"rsa-sha2-256" -> :rsa
      :"rsa-sha2-512" -> :rsa
      :"ecdsa-sha2-nistp256" -> :ecdsa
      :"ecdsa-sha2-nistp384" -> :ecdsa
      :"ecdsa-sha2-nistp521" -> :ecdsa
      _ -> nil
    end
  end

  defp key_type(key) do
    case key do
      {:ed_pri, :ed25519, _, _} -> :ed25519
      {:ed_pri, :ed448, _, _} -> :ed448
      # OTP 28 may represent Ed25519/Ed448 as ECPrivateKey with a namedCurve OID
      {:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 112}}, _, _} -> :ed25519
      {:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 113}}, _, _} -> :ed448
      # ECDSA curves (NIST P-256/P-384/P-521)
      {:ECPrivateKey, _, _, {:namedCurve, _}, _, _} -> :ecdsa
      {:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _} -> :rsa
      _ -> :unknown
    end
  end

  defp decode_pem_key(data) do
    case :public_key.pem_decode(data) do
      [{_type, _der, _info} = entry | _] ->
        key = :public_key.pem_entry_decode(entry)
        {:ok, key}

      _ ->
        {:error, :pem_decode_failed}
    end
  rescue
    _ -> {:error, :pem_decode_failed}
  catch
    _, _ -> {:error, :pem_decode_failed}
  end
end
