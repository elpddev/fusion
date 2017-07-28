defmodule Fusion.Utilities.Ssh do
  @moduledoc """

  ## Ssh command options been used:

  * -p: Port to connect to on the remote host.
  * -n: Prevent reading from stdin. Our command is used to tunnel traffic so no need for terminal allocation. # todo: more technical accurate explanation. 
  * -N: Tell ssh not to perform a command after login to the remote server and just do other things  
        like forwarding ports.          
  * -T: disable pseudo-tty allocation.  
  * -R: bind local port to remote host and port.
  """
    
  alias Fusion.Net.Spot
  alias Fusion.Utilities.Bash

  @default_ssh_path "/usr/bin/env ssh"  
  @default_sshpass_path "/usr/bin/env sshpass"

  @doc """
  
  ## Examples

  iex> partial_cmd_sshpass("abcd1234!", "/usr/bin/sshpass")
  "/usr/bin/sshpass -p abcd1234!"

  """
  def partial_cmd_sshpass(password, sshpass_path \\ @default_sshpass_path) do
    [
      sshpass_path,
      "-p #{password}"
    ] |> Enum.join(" ")
  end
  
  @doc """
  Generate partial params for ssh command to create reverse(remote -> local) tunnel.

  ## Examples

  iex> partial_cmd_reverse_tunnel(9004, %Fusion.Net.Spot{host: "localhost", port: 8003})
  "-nNT -R 9004:localhost:8003"

  """
  def partial_cmd_reverse_tunnel(from_port, %Spot{} = to_spot) do
    "-nNT -R #{from_port}:#{to_spot.host}:#{to_spot.port}"
  end

  @doc """
  Generate partial params for ssh command to create forward(local -> remote) tunnel.

  ## Examples

  iex> partial_cmd_forward_tunnel(9004, %Fusion.Net.Spot{host: "localhost", port: 8003})
  "-nNT -4 -L 9004:localhost:8003"

  """
  def partial_cmd_forward_tunnel(from_port, %Spot{} = to_spot) do
    "-nNT -4 -L #{from_port}:#{to_spot.host}:#{to_spot.port}"
  end

  @doc """

  ## Examples

  iex> cmd("-nNT -R 3001:localhost:3002", %{username: "john", password: "abcd1234"},
  ...>  %Fusion.Net.Spot{host: "example.com", port: 22})
  "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -p 22 -nNT -R 3001:localhost:3002 john@example.com"

  iex> cmd("-nNT -R 3001:localhost:3002", %{username: "john", key_path: "/home/john/.ssh/id_rsa"},
  ...>  %Fusion.Net.Spot{host: "example.com", port: 22})
  "/usr/bin/env ssh -p 22 -i /home/john/.ssh/id_rsa -nNT -R 3001:localhost:3002 john@example.com"

  """
  def cmd(cmd, auth, remote, ssh_path \\ @default_ssh_path)

  def cmd(cmd, %{username: username, password: password}, 
          %Spot{} = remote, ssh_path) do
    "#{partial_cmd_sshpass(password)} #{ssh_path} -p #{remote.port} #{cmd} #{username}@#{remote.host}"
  end

  def cmd(cmd, %{username: username, key_path: key_path}, 
          %Spot{} = remote, ssh_path) do

    "#{ssh_path} -p #{remote.port} -i #{key_path} #{cmd} #{username}@#{remote.host}"
  end

  def cmd_remote(remote_cmd, auth, remote) do
    cmd("", auth, remote) <> " " <>
    "\"#{remote_cmd |> Bash.escape_str()}\""
  end

  @doc """

  ## Examples
  
  iex> cmd_port_tunnel(%{username: "john", password: "abcd1234"}, 
  ...>   %Fusion.Net.Spot{host: "example.com", port: 22}, 
  ...>   4567, 
  ...>   %Fusion.Net.Spot{host: "localhost", port: 2345}, 
  ...>   :reverse)
  "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -p 22 -nNT -R 4567:localhost:2345 john@example.com"
  """
  def cmd_port_tunnel(auth, %Spot{} = remote, from_port, %Spot{} = to_spot, :reverse) do
    partial_cmd_reverse_tunnel(from_port, to_spot)
    |> cmd(auth, remote)
  end

  @doc """

  ## Examples
  
  iex> cmd_port_tunnel(%{username: "john", password: "abcd1234"}, %Fusion.Net.Spot{host: "example.com", port: 22}, 4567, %Fusion.Net.Spot{host: "localhost", port: 2345}, :forward)
  "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -p 22 -nNT -4 -L 4567:localhost:2345 john@example.com"
  """
  def cmd_port_tunnel(auth, remote, from_port, %Spot{} = to_spot, :forward) do
    partial_cmd_forward_tunnel(from_port, to_spot)
    |> cmd(auth, remote)
  end

end
