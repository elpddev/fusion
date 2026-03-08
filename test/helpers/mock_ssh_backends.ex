defmodule Fusion.Test.MockBackend do
  @moduledoc false
  @behaviour Fusion.SshBackend

  @mock_async_timeout 5_000

  @impl true
  def connect(_target), do: {:ok, :mock_conn}

  @impl true
  def forward_tunnel(_conn, port, _host, _remote_port), do: {:ok, port}

  @impl true
  def reverse_tunnel(_conn, port, _host, _remote_port), do: {:ok, port}

  @impl true
  def exec(_conn, _cmd), do: {:ok, ""}

  @impl true
  def exec_async(_conn, _cmd) do
    pid =
      spawn(fn ->
        receive do
          :stop -> :ok
        after
          @mock_async_timeout -> :ok
        end
      end)

    {:ok, pid}
  end

  @impl true
  def close(_conn), do: :ok
end

defmodule Fusion.Test.TrackingMockBackend do
  @moduledoc false
  @behaviour Fusion.SshBackend

  alias Fusion.Test.MockBackend

  @impl true
  defdelegate connect(target), to: MockBackend

  @impl true
  defdelegate forward_tunnel(conn, port, host, remote_port), to: MockBackend

  @impl true
  defdelegate reverse_tunnel(conn, port, host, remote_port), to: MockBackend

  @impl true
  defdelegate exec(conn, cmd), to: MockBackend

  @impl true
  defdelegate exec_async(conn, cmd), to: MockBackend

  @impl true
  def close(conn) when is_atom(conn) do
    table = :"tracking_mock_#{conn}"

    if :ets.whereis(table) != :undefined do
      :ets.update_counter(table, :close_count, 1, {:close_count, 0})
    end

    :ok
  end

  @impl true
  def close(_conn), do: :ok
end

defmodule Fusion.Test.FailConnectBackend do
  @moduledoc false
  @behaviour Fusion.SshBackend

  alias Fusion.Test.MockBackend

  @impl true
  def connect(_target), do: {:error, :connection_refused}

  @impl true
  defdelegate forward_tunnel(conn, port, host, remote_port), to: MockBackend

  @impl true
  defdelegate reverse_tunnel(conn, port, host, remote_port), to: MockBackend

  @impl true
  defdelegate exec(conn, cmd), to: MockBackend

  @impl true
  defdelegate exec_async(conn, cmd), to: MockBackend

  @impl true
  defdelegate close(conn), to: MockBackend
end

defmodule Fusion.Test.FailExecAsyncBackend do
  @moduledoc false
  @behaviour Fusion.SshBackend

  alias Fusion.Test.MockBackend

  @impl true
  defdelegate connect(target), to: MockBackend

  @impl true
  defdelegate forward_tunnel(conn, port, host, remote_port), to: MockBackend

  @impl true
  defdelegate reverse_tunnel(conn, port, host, remote_port), to: MockBackend

  @impl true
  defdelegate exec(conn, cmd), to: MockBackend

  @impl true
  def exec_async(_conn, _cmd), do: {:error, :exec_async_failed}

  @impl true
  defdelegate close(conn), to: MockBackend
end

defmodule Fusion.Test.FailTunnelBackend do
  @moduledoc false
  @behaviour Fusion.SshBackend

  alias Fusion.Test.MockBackend

  @impl true
  defdelegate connect(target), to: MockBackend

  @impl true
  def forward_tunnel(_conn, _port, _host, _remote_port), do: {:error, :tunnel_failed}

  @impl true
  def reverse_tunnel(_conn, _port, _host, _remote_port), do: {:error, :tunnel_failed}

  @impl true
  defdelegate exec(conn, cmd), to: MockBackend

  @impl true
  defdelegate exec_async(conn, cmd), to: MockBackend

  @impl true
  defdelegate close(conn), to: MockBackend
end
