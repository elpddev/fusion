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
  "socat udp4-listen:1234,reuseaddr,fork TCP:localhost:4567"
  """ 
  def cmd_udp_listner_to_tcp(listener_port, target_port) do
    "socat udp4-listen:#{listener_port},reuseaddr,fork TCP:localhost:#{target_port}"
  end 
      
  @doc """
  Generate socat command for activating a tcp4 listener and direct the traffic out as udp to a target port.
    
  ## Examples                           
  
  iex> cmd_tcp_listener_to_udp(1234, 4567) 
  "socat tcp4-listen:1234,reuseaddr,fork UDP:localhost:4567"
  """
  def cmd_tcp_listener_to_udp(listener_port, target_port) do
    "socat tcp4-listen:#{listener_port},reuseaddr,fork UDP:localhost:#{target_port}"
  end

end
