defmodule Fusion.Utilities.Socat do
  @moduledoc """                        
  A wrapper module around the socat cli utility.

  ## Socat cli options used:            
  
  * UDP-LISTEN:<port> - listen on a udp port.
  * UDP4-LISTEN:<port> -                
  * TCP-LISTEN:<port> - listen on a tcp port.
  * TCP4-LISTEN:<port> -                
  * TCP:<host>:<port> - output the incoming traffic to the tcp address.
  * TCP4:<host>:<port> -                
  * UDP:<host>:<port> - output the incoming traffic to the udp address.
  * UDP4:<host>:<port> -                

  * reuseaddr - allow others to listen and the same port
  * fork - 
      
  """ 
    
  @doc """                              
  Generate socat command for activating udp4 listener and direct the trafic out as tcp to a target port. 
  ## Examples                           
        
  iex> cmd_udp_listner_to_tcp(1234, 4567)  
  "socat udp4-listen:1234,reuseaddr,fork,bind=127.0.0.1 TCP:localhost:4567"
  """ 
  def cmd_udp_listner_to_tcp(listener_port, target_port) do
    "socat udp4-listen:#{listener_port},reuseaddr,fork,bind=127.0.0.1 TCP:localhost:#{target_port}"
  end 
      
  @doc """
  Generate socat command for activating a tcp4 listener and direct the traffic out as udp to a target port.
    
  ## Examples                           
  
  iex> cmd_tcp_listener_to_udp(1234, 4567) 
  "socat tcp4-listen:1234,reuseaddr,fork,bind=127.0.0.1 UDP:localhost:4567"
  """
  def cmd_tcp_listener_to_udp(listener_port, target_port) do
    "socat tcp4-listen:#{listener_port},reuseaddr,fork,bind=127.0.0.1 UDP:localhost:#{target_port}"
  end

  @doc """
  Generate socat command.
    
  ## Examples                           
  
  iex> cmd(1234, :tcp, 4567, :udp) 
  "socat tcp4-listen:1234,reuseaddr,fork,bind=127.0.0.1 UDP:localhost:4567"

  iex> cmd(1234, :udp, 4567, :tcp) 
  "socat udp4-listen:1234,reuseaddr,fork,bind=127.0.0.1 TCP:localhost:4567"
  """
  def cmd(from_port, from_type, to_port, to_type) do
    case {from_type, to_type} do
      {:tcp, :udp} -> cmd_tcp_listener_to_udp(from_port, to_port)
      {:udp, :tcp} -> cmd_udp_listner_to_tcp(from_port, to_port)
      _ -> {:error, "unimplemented from/to port type combination"}
    end
  end

  @doc """
  Generate socat command for udp echo server.
    
  ## Examples                           
  
  iex> cmd_udp_echo_server(1200) 
  "socat PIPE udp-recvfrom:1200,fork"
  """
  def cmd_udp_echo_server(port) do
    "socat PIPE udp-recvfrom:#{port},fork"
  end
end
