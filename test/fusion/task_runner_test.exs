defmodule Fusion.TaskRunnerTest do
  use ExUnit.Case, async: true

  alias Fusion.TaskRunner

  describe "get_module_bytecode/1" do
    test "returns bytecode for a loaded module" do
      assert {:ok, {Kernel, binary, filename}} = TaskRunner.get_module_bytecode(Kernel)
      assert is_binary(binary)
      assert byte_size(binary) > 0
      assert is_list(filename)
    end

    test "returns bytecode for Fusion module itself" do
      assert {:ok, {Fusion.TaskRunner, binary, _filename}} =
               TaskRunner.get_module_bytecode(Fusion.TaskRunner)

      assert is_binary(binary)
    end

    test "returns error for non-existent module" do
      assert {:error, {:module_not_found, NonExistentModule}} =
               TaskRunner.get_module_bytecode(NonExistentModule)
    end
  end

  describe "run/5 on local node" do
    test "executes MFA on the local node" do
      # We can test against the local node itself
      local = node()
      assert {:ok, 3} = TaskRunner.run(local, Kernel, :+, [1, 2])
    end

    test "executes String function on local node" do
      local = node()
      assert {:ok, "HELLO"} = TaskRunner.run(local, String, :upcase, ["hello"])
    end

    test "returns error for undefined function" do
      local = node()
      assert {:error, _} = TaskRunner.run(local, Kernel, :nonexistent_function, [])
    end
  end

  describe "run_fun/3 on local node" do
    test "executes anonymous function on local node" do
      local = node()
      assert {:ok, 42} = TaskRunner.run_fun(local, fn -> 21 * 2 end)
    end

    test "executes function that captures local state" do
      local = node()
      x = 10
      assert {:ok, 20} = TaskRunner.run_fun(local, fn -> x * 2 end)
    end
  end

  describe "push_module/2" do
    test "pushes a module to the local node" do
      local = node()
      assert :ok = TaskRunner.push_module(local, Enum)
    end

    test "returns error for non-existent module" do
      local = node()
      assert {:error, {:module_not_found, FakeModule}} = TaskRunner.push_module(local, FakeModule)
    end
  end

  describe "get_module_dependencies/1" do
    test "returns non-stdlib dependencies for a module" do
      # RemoteFuns.make_spot/1 references Fusion.Net.Spot
      deps = TaskRunner.get_module_dependencies(Fusion.Test.Helpers.RemoteFuns)
      assert Fusion.Net.Spot in deps
    end

    test "does not include stdlib modules" do
      deps = TaskRunner.get_module_dependencies(Fusion.Test.Helpers.RemoteFuns)
      refute Kernel in deps
      refute Enum in deps
    end

    test "returns empty list for unknown module" do
      assert [] = TaskRunner.get_module_dependencies(NonExistentModule)
    end
  end

  describe "push_modules/2" do
    test "pushes multiple modules" do
      local = node()
      assert :ok = TaskRunner.push_modules(local, [Enum, Map, String])
    end

    test "returns error on first failure" do
      local = node()

      assert {:error, {FakeModule, {:module_not_found, FakeModule}}} =
               TaskRunner.push_modules(local, [Enum, FakeModule, Map])
    end
  end
end
