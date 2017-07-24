defmodule Fusion.Test.Helpers.Docker do

  alias Fusion.Net.Spot

  def init_docker_container(image_name) do
    %{"Id" => container_id, "Warnings" => _} = Dockerex.Client.post("containers/create", %{
      "Image": image_name,
      "Tty": true,
    })

    nil = Dockerex.Client.post("containers/#{container_id}/start")

    %{ "NetworkSettings" => %{"Networks" => %{"bridge" => %{"IPAddress" => container_ip }}}} =
      Dockerex.Client.get("containers/#{container_id}/json")

    %{auth: auth, ssh_port: ssh_port} = get_image_info(image_name)

    %{
      container_id: container_id,
      server: %Spot{host: container_ip, port: ssh_port},
      auth: auth
    }   
  end 

  def get_image_info("fusion_tester") do
    %{
      auth: %{username: "test_user", password: "test_password"},
      ssh_port: 22
    }
  end
      
  def docker_conf_expose(test_port) do  
    %{
      "ExposedPorts": %{                
        "20000/tcp": %{}                
      },
      "HostConfig": %{                  
        "PortBindings": %{
          "#{test_port}/tcp": [         
            %{
              "HostPort": "#{test_port}"
            }
          ]
        },
      },
    } 
  end 
    
  def remove_docker_container(container_id) do
    #Dockerex.Client.post("containers/#{container_id}/stop", %{ "t" => 15 }, 
    #  default_headers(), recv_timeout: 15000)
    Dockerex.Client.post("containers/#{container_id}/kill", %{}, default_headers(), recv_timeout: 15000)

    Dockerex.Client.delete("containers/#{container_id}") 
  end

  def default_headers do
    {:ok , hostname} = :inet.gethostname
    %{"Content-Type" => "application/json", "Host" => hostname}
  end
end
