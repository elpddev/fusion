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
  def sign(key, data, opts) do
    # Prefer the hash algorithm from OTP's negotiation opts (e.g., rsa-sha2-512),
    # falling back to our key-type-based default.
    hash = Keyword.get(opts, :hash) || hash_for_key(key)
    :public_key.sign(data, hash, key)
  end

  # Ed25519/Ed448 — EdDSA does its own hashing
  defp hash_for_key({:ed_pri, _, _, _}), do: :none
  defp hash_for_key({:ed_pub, _, _}), do: :none
  # OTP 28 may represent Ed25519/Ed448 as ECPrivateKey with curve OIDs
  defp hash_for_key({:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 112}}, _, _}), do: :none
  defp hash_for_key({:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 113}}, _, _}), do: :none
  # ECDSA (NIST curves)
  defp hash_for_key({:ECPrivateKey, _, _, _, _, _}), do: :sha256
  # RSA — use sha256 for rsa-sha2-256 (modern default)
  defp hash_for_key(_), do: :sha256

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

  defp key_type_for_algorithm(:"ssh-ed25519"), do: :ed25519
  defp key_type_for_algorithm(:"ssh-ed448"), do: :ed448
  defp key_type_for_algorithm(:"ssh-rsa"), do: :rsa
  defp key_type_for_algorithm(:"rsa-sha2-256"), do: :rsa
  defp key_type_for_algorithm(:"rsa-sha2-512"), do: :rsa
  defp key_type_for_algorithm(:"ecdsa-sha2-nistp256"), do: :ecdsa
  defp key_type_for_algorithm(:"ecdsa-sha2-nistp384"), do: :ecdsa
  defp key_type_for_algorithm(:"ecdsa-sha2-nistp521"), do: :ecdsa
  defp key_type_for_algorithm(_), do: nil

  defp key_type({:ed_pri, :ed25519, _, _}), do: :ed25519
  defp key_type({:ed_pri, :ed448, _, _}), do: :ed448
  # OTP 28 may represent Ed25519/Ed448 as ECPrivateKey with namedCurve OIDs
  defp key_type({:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 112}}, _, _}), do: :ed25519
  defp key_type({:ECPrivateKey, _, _, {:namedCurve, {1, 3, 101, 113}}, _, _}), do: :ed448
  # ECDSA curves (NIST P-256/P-384/P-521)
  defp key_type({:ECPrivateKey, _, _, {:namedCurve, _}, _, _}), do: :ecdsa
  defp key_type({:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _}), do: :rsa
  defp key_type(_), do: :unknown

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
