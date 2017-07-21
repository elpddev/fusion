# Fusion

A remote server connection and control library.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `fusion` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:fusion, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/fusion](https://hexdocs.pm/fusion).

## Development

### Testing

#### Using Docker

In the external text, setup the starting of the needed started application and for each test, the initialization of the required container.

```elixir
alias Fusion.Test.Helpers.Docker

setup_all _context do
  Application.ensure_started(:dockerex)
  HTTPoison.start # dockerex dependecy
  :ok
end

setup _context do                      
  %{ container_id: container_id, server: server, auth: auth } = 
    Docker.init_docker_container("fusion_tester")

  Process.sleep(1000)                 
    
  on_exit fn ->                       
    Process.sleep(500)                
    Docker.remove_docker_container(container_id)
  end 
      
  {:ok, [ auth: auth, server: server, container_id: container_id, ]} 
end
```
