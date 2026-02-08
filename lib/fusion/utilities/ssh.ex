defmodule Fusion.Utilities.Ssh do
  @moduledoc """
  SSH command string generation.

  ## SSH command options used:

  * -p: Port to connect to on the remote host.
  * -n: Prevent reading from stdin.
  * -N: Do not execute a remote command (just forward ports).
  * -T: Disable pseudo-tty allocation.
  * -R: Reverse tunnel - bind remote port to local host:port.
  * -L: Forward tunnel - bind local port to remote host:port.
  * -4: Force IPv4.
  """

  alias Fusion.Net.Spot
  alias Fusion.Utilities.Bash

  @default_ssh_path "/usr/bin/env ssh"
  @default_sshpass_path "/usr/bin/env sshpass"
  @default_ssh_opts "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

  @doc """
  Generate sshpass prefix for password authentication.

  ## Examples

      iex> Fusion.Utilities.Ssh.partial_cmd_sshpass("abcd1234!", "/usr/bin/sshpass")
      "/usr/bin/sshpass -p abcd1234!"
  """
  def partial_cmd_sshpass(password, sshpass_path \\ @default_sshpass_path) do
    "#{sshpass_path} -p #{password}"
  end

  @doc """
  Generate reverse tunnel SSH flags.

  ## Examples

      iex> Fusion.Utilities.Ssh.partial_cmd_reverse_tunnel(9004, %Fusion.Net.Spot{host: "localhost", port: 8003})
      "-nNT -R 9004:localhost:8003"
  """
  def partial_cmd_reverse_tunnel(from_port, %Spot{} = to_spot) do
    "-nNT -R #{from_port}:#{to_spot.host}:#{to_spot.port}"
  end

  @doc """
  Generate forward tunnel SSH flags.

  ## Examples

      iex> Fusion.Utilities.Ssh.partial_cmd_forward_tunnel(9004, %Fusion.Net.Spot{host: "localhost", port: 8003})
      "-nNT -4 -L 9004:localhost:8003"
  """
  def partial_cmd_forward_tunnel(from_port, %Spot{} = to_spot) do
    "-nNT -4 -L #{from_port}:#{to_spot.host}:#{to_spot.port}"
  end

  @doc """
  Generate a full SSH command string.

  ## Examples

      iex> Fusion.Utilities.Ssh.cmd("-nNT -R 3001:localhost:3002", %{username: "john", password: "abcd1234"},
      ...>  %Fusion.Net.Spot{host: "example.com", port: 22})
      "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 22 -nNT -R 3001:localhost:3002 john@example.com"

      iex> Fusion.Utilities.Ssh.cmd("-nNT -R 3001:localhost:3002", %{username: "john", key_path: "/home/john/.ssh/id_rsa"},
      ...>  %Fusion.Net.Spot{host: "example.com", port: 22})
      "/usr/bin/env ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 22 -i /home/john/.ssh/id_rsa -nNT -R 3001:localhost:3002 john@example.com"
  """
  def cmd(cmd, auth, remote, ssh_path \\ @default_ssh_path)

  def cmd(cmd, %{username: username, password: password}, %Spot{} = remote, ssh_path) do
    "#{partial_cmd_sshpass(password)} #{ssh_path} #{@default_ssh_opts} -p #{remote.port} #{cmd} #{username}@#{remote.host}"
  end

  def cmd(cmd, %{username: username, key_path: key_path}, %Spot{} = remote, ssh_path) do
    "#{ssh_path} #{@default_ssh_opts} -p #{remote.port} -i #{key_path} #{cmd} #{username}@#{remote.host}"
  end

  @doc "Generate an SSH command to execute a remote command."
  def cmd_remote(remote_cmd, auth, remote) do
    cmd("", auth, remote) <> " " <> "\"#{Bash.escape_str(remote_cmd)}\""
  end

  @doc """
  Generate a full SSH port tunnel command.

  ## Examples

      iex> Fusion.Utilities.Ssh.cmd_port_tunnel(%{username: "john", password: "abcd1234"},
      ...>   %Fusion.Net.Spot{host: "example.com", port: 22},
      ...>   4567,
      ...>   %Fusion.Net.Spot{host: "localhost", port: 2345},
      ...>   :reverse)
      "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 22 -nNT -R 4567:localhost:2345 john@example.com"

      iex> Fusion.Utilities.Ssh.cmd_port_tunnel(%{username: "john", password: "abcd1234"},
      ...>   %Fusion.Net.Spot{host: "example.com", port: 22},
      ...>   4567,
      ...>   %Fusion.Net.Spot{host: "localhost", port: 2345},
      ...>   :forward)
      "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 22 -nNT -4 -L 4567:localhost:2345 john@example.com"
  """
  def cmd_port_tunnel(auth, %Spot{} = remote, from_port, %Spot{} = to_spot, :reverse) do
    partial_cmd_reverse_tunnel(from_port, to_spot)
    |> cmd(auth, remote)
  end

  def cmd_port_tunnel(auth, %Spot{} = remote, from_port, %Spot{} = to_spot, :forward) do
    partial_cmd_forward_tunnel(from_port, to_spot)
    |> cmd(auth, remote)
  end
end
