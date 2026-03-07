defmodule Fusion.Test.MockBackend do
  @behaviour Fusion.SshBackend

  @impl true
  def connect(_target), do: {:ok, :mock_conn}

  @impl true
  def forward_tunnel(_c, port, _h, _p), do: {:ok, port}

  @impl true
  def reverse_tunnel(_c, port, _h, _p), do: {:ok, port}

  @impl true
  def exec(_c, _cmd), do: {:ok, ""}

  @impl true
  def exec_async(_c, _cmd), do: {:ok, spawn(fn -> :ok end)}

  @impl true
  def close(_c), do: :ok
end

defmodule Fusion.Test.FailConnectBackend do
  @behaviour Fusion.SshBackend

  @impl true
  def connect(_target), do: {:error, :connection_refused}

  @impl true
  def forward_tunnel(_c, _p, _h, _p2), do: {:error, :not_connected}

  @impl true
  def reverse_tunnel(_c, _p, _h, _p2), do: {:error, :not_connected}

  @impl true
  def exec(_c, _cmd), do: {:error, :not_connected}

  @impl true
  def exec_async(_c, _cmd), do: {:error, :not_connected}

  @impl true
  def close(_c), do: :ok
end

defmodule Fusion.Test.FailTunnelBackend do
  @behaviour Fusion.SshBackend

  @impl true
  def connect(_target), do: {:ok, :mock_conn}

  @impl true
  def forward_tunnel(_c, _p, _h, _p2), do: {:error, :tunnel_failed}

  @impl true
  def reverse_tunnel(_c, _p, _h, _p2), do: {:error, :tunnel_failed}

  @impl true
  def exec(_c, _cmd), do: {:ok, ""}

  @impl true
  def exec_async(_c, _cmd), do: {:ok, spawn(fn -> :ok end)}

  @impl true
  def close(_c), do: :ok
end
