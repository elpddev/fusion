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

  # RFC 8410 OIDs for EdDSA curves
  @oid_ed25519 {1, 3, 101, 112}
  @oid_ed448 {1, 3, 101, 113}

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
      {:ok, key_data} ->
        case decode_private_key(key_data) do
          {:ok, key} ->
            expected = key_type_for_algorithm(algorithm)
            actual = key_type(key)

            # nil means unknown algorithm — skip the check rather than false-positive
            if expected != nil and expected != actual do
              Logger.warning(
                "SSH key type mismatch: requested #{algorithm} but key at #{key_path} is #{actual}"
              )

              {:error, :key_type_mismatch}
            else
              {:ok, key}
            end

          error ->
            error
        end

      {:error, reason} ->
        {:error, {:file_read_error, key_path, reason}}
    end
  end

  defp decode_private_key(data) do
    # Try OpenSSH key v1 format first (modern ssh-keygen default),
    # then fall back to PEM format for older keys.
    # Short-circuit on definitive errors like :encrypted_key.
    case decode_openssh_key(data) do
      {:ok, _} = ok -> ok
      {:error, :encrypted_key} = err -> err
      {:error, _} -> fallback_decode_pem_key(data)
    end
  end

  defp fallback_decode_pem_key(data) do
    case decode_pem_key(data) do
      {:ok, _} = ok -> ok
      {:error, :encrypted_key} = err -> err
      {:error, _} -> {:error, :unsupported_key_format}
    end
  end

  defp decode_openssh_key(data) do
    case :ssh_file.decode(data, :openssh_key_v1) do
      [{key, _attrs} | _] ->
        {:ok, key}

      _ ->
        # Decode failed — check if the key is encrypted (cipher != "none").
        # OpenSSH v1 keys embed encryption info in the binary, not the PEM wrapper.
        if openssh_key_encrypted?(data),
          do: {:error, :encrypted_key},
          else: {:error, :openssh_decode_failed}
    end
  rescue
    e ->
      Logger.debug("OpenSSH key decode raised: #{inspect(e)}")
      {:error, :openssh_decode_failed}
  catch
    _, reason ->
      Logger.debug("OpenSSH key decode threw: #{inspect(reason)}")
      {:error, :openssh_decode_failed}
  end

  # Check if an OpenSSH v1 key is encrypted by inspecting the cipher field.
  # Format: "openssh-key-v1\0" + uint32 cipher_len + cipher_name + ...
  # Unencrypted keys use cipher "none".
  defp openssh_key_encrypted?(pem_data) do
    case :public_key.pem_decode(pem_data) do
      [{_type, der, _info} | _] ->
        case der do
          <<"openssh-key-v1", 0, len::32, cipher::binary-size(len), _::binary>> ->
            cipher != "none"

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp decode_pem_key(data) do
    case :public_key.pem_decode(data) do
      [{_type, _der, :not_encrypted} = entry | _] ->
        key = :public_key.pem_entry_decode(entry)
        {:ok, key}

      [{_type, _der, _encryption_info} | _] ->
        {:error, :encrypted_key}

      _ ->
        {:error, :pem_decode_failed}
    end
  rescue
    e ->
      Logger.debug("PEM key decode raised: #{inspect(e)}")
      {:error, :pem_decode_failed}
  catch
    _, reason ->
      Logger.debug("PEM key decode threw: #{inspect(reason)}")
      {:error, :pem_decode_failed}
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
  defp key_type({:ECPrivateKey, _, _, {:namedCurve, @oid_ed25519}, _, _}), do: :ed25519
  defp key_type({:ECPrivateKey, _, _, {:namedCurve, @oid_ed448}, _, _}), do: :ed448
  # ECDSA curves (NIST P-256/P-384/P-521)
  defp key_type({:ECPrivateKey, _, _, {:namedCurve, _}, _, _}), do: :ecdsa
  defp key_type({:RSAPrivateKey, _, _, _, _, _, _, _, _, _, _}), do: :rsa
  defp key_type(_), do: :unknown
end
