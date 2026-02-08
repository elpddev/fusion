defmodule Fusion.TaskRunner do
  @moduledoc """
  Executes Elixir code on remote BEAM nodes.

  Handles pushing compiled module bytecode to the remote node before execution,
  so modules defined locally can run remotely without pre-installation.

  Uses `:erpc` for remote calls (OTP 23+), which provides better error handling
  than the older `:rpc` module.
  """

  @default_timeout 30_000

  @doc """
  Run a function on the remote node (MFA form).

  Pushes the module's bytecode to the remote node if needed, then calls
  `module.function(args)` remotely.

  Returns `{:ok, result}` or `{:error, reason}`.

  ## Examples

      {:ok, 3} = Fusion.TaskRunner.run(remote_node, Kernel, :+, [1, 2])
  """
  def run(node, module, function, args, opts \\ [])
      when is_atom(node) and is_atom(module) and is_atom(function) and is_list(args) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with :ok <- ensure_module_available(node, module) do
      call(node, module, function, args, timeout)
    end
  end

  @doc """
  Run an anonymous function on the remote node.

  Extracts the module that defines the anonymous function, pushes its bytecode
  to the remote node, then executes the function remotely.

  Returns `{:ok, result}` or `{:error, reason}`.

  ## Examples

      {:ok, 2} = Fusion.TaskRunner.run_fun(remote_node, fn -> 1 + 1 end)
  """
  def run_fun(node, fun, opts \\ []) when is_atom(node) and is_function(fun) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    info = Function.info(fun)
    module = Keyword.fetch!(info, :module)

    with :ok <- ensure_module_available(node, module) do
      call_fun(node, fun, timeout)
    end
  end

  @doc """
  Push a module's bytecode to the remote node.

  Returns `:ok` or `{:error, reason}`.
  """
  def push_module(node, module) when is_atom(node) and is_atom(module) do
    ensure_module_available(node, module)
  end

  @doc """
  Push multiple modules to the remote node.

  Returns `:ok` or `{:error, {module, reason}}` for the first failure.
  """
  def push_modules(node, modules) when is_atom(node) and is_list(modules) do
    Enum.reduce_while(modules, :ok, fn module, :ok ->
      case ensure_module_available(node, module) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {module, reason}}}
      end
    end)
  end

  @doc """
  Get the bytecode binary for a module.

  Returns `{:ok, {module, binary, filename}}` or `{:error, reason}`.
  """
  def get_module_bytecode(module) when is_atom(module) do
    case :code.get_object_code(module) do
      {^module, binary, filename} -> {:ok, {module, binary, filename}}
      :error -> {:error, {:module_not_found, module}}
    end
  end

  @doc """
  Get the list of non-stdlib modules that a module references.

  Parses the BEAM bytecode atoms table to find referenced modules
  (covers function calls, struct usage, and protocol references),
  then filters out Erlang/OTP and Elixir stdlib modules.

  Returns a list of module atoms.
  """
  def get_module_dependencies(module) when is_atom(module) do
    with {:ok, {_module, binary, _filename}} <- get_module_bytecode(module),
         {:ok, {_module, [{:atoms, atoms}]}} <- safe_beam_chunks(binary, :atoms) do
      atoms
      |> Enum.map(fn {_index, atom} -> atom end)
      |> Enum.filter(&elixir_module?/1)
      |> Enum.reject(&(&1 == module))
      |> Enum.reject(&stdlib_module?/1)
    else
      _ -> []
    end
  end

  ## Private

  defp ensure_module_available(node, module) do
    ensure_module_with_deps(node, module, MapSet.new())
  end

  defp ensure_module_with_deps(node, module, visited) do
    if MapSet.member?(visited, module) do
      :ok
    else
      visited = MapSet.put(visited, module)

      # Check if already loaded on remote
      case :erpc.call(node, :code, :is_loaded, [module]) do
        {:file, _} ->
          :ok

        false ->
          # Push dependencies first (bottom-up), then the module itself
          with :ok <- push_dependencies(node, module, visited),
               :ok <- push_module_bytecode(node, module) do
            :ok
          end
      end
    end
  rescue
    e -> {:error, {:check_failed, e}}
  end

  defp push_dependencies(node, module, visited) do
    deps = get_module_dependencies(module)

    Enum.reduce_while(deps, :ok, fn dep, :ok ->
      case ensure_module_with_deps(node, dep, visited) do
        :ok -> {:cont, :ok}
        # Skip modules we can't find locally (OTP modules missed by filter, etc.)
        {:error, {:module_not_found, _}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp stdlib_module?(module) do
    case :code.which(module) do
      :preloaded -> true
      :cover_compiled -> true
      path when is_list(path) -> not String.contains?(List.to_string(path), "_build/")
      _ -> true
    end
  end

  defp elixir_module?(atom) when is_atom(atom) do
    # Elixir modules are atoms starting with "Elixir." (e.g., Fusion.Net.Spot)
    # Erlang modules are lowercase atoms (e.g., :erlang, :lists)
    atom |> Atom.to_string() |> String.starts_with?("Elixir.")
  end

  defp safe_beam_chunks(binary, chunk_type) do
    :beam_lib.chunks(binary, [chunk_type])
  rescue
    _ -> :error
  end

  defp push_module_bytecode(node, module) do
    case get_module_bytecode(module) do
      {:ok, {^module, binary, filename}} ->
        case :erpc.call(node, :code, :load_binary, [module, filename, binary]) do
          {:module, ^module} -> :ok
          {:error, reason} -> {:error, {:load_failed, module, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:push_failed, module, e}}
  end

  defp call(node, module, function, args, timeout) do
    result = :erpc.call(node, module, function, args, timeout)
    {:ok, result}
  rescue
    e -> {:error, {:call_failed, e}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp call_fun(node, fun, timeout) do
    result = :erpc.call(node, fun, timeout)
    {:ok, result}
  rescue
    e -> {:error, {:call_failed, e}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end
