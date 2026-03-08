defmodule Fusion.Test.SshBackendSharedTests do
  @moduledoc false

  defmacro assert_implements_ssh_backend(module) do
    quote do
      test "implements the SshBackend behaviour" do
        behaviours =
          unquote(module).__info__(:attributes)
          |> Keyword.get_values(:behaviour)
          |> List.flatten()

        assert Fusion.SshBackend in behaviours
      end

      test "exports all required callback functions" do
        Code.ensure_loaded!(unquote(module))

        for {fun, arity} <- [
              connect: 1,
              forward_tunnel: 4,
              reverse_tunnel: 4,
              exec: 2,
              exec_async: 2,
              close: 1
            ] do
          assert function_exported?(unquote(module), fun, arity),
                 "expected #{inspect(unquote(module))}.#{fun}/#{arity} to be exported"
        end
      end
    end
  end
end
