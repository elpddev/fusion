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
  ...>  "example.com")
  "/usr/bin/env sshpass -p abcd1234 /usr/bin/env ssh -nNT -R 3001:localhost:3002 john@example.com"

  iex> cmd("-nNT -R 3001:localhost:3002", %{username: "john", key_path: "/home/john/.ssh/id_rsa"},
  ...>  "example.com")
  "/usr/bin/env ssh -i /home/john/.ssh/id_rsa -nNT -R 3001:localhost:3002 john@example.com"

  """
  def cmd(cmd, auth, host, ssh_path \\ @default_ssh_path)

  def cmd(cmd, %{username: username, password: password}, host, ssh_path) do
    "#{partial_cmd_sshpass(password)} #{ssh_path} #{cmd} #{username}@#{host}"
  end

  def cmd(cmd, %{username: username, key_path: key_path}, host, ssh_path) do

    "#{ssh_path} -i #{key_path} #{cmd} #{username}@#{host}"
  end
end
