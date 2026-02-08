defmodule Fusion.Test.Helpers.Docker do
  @moduledoc "Docker container management for external tests."

  @container_name "fusion_test_ssh"
  @ssh_port 2222
  @username "fusion_test"
  @password "fusion_pass"

  @doc "Check if the test container is running."
  def container_running? do
    {output, 0} = System.cmd("docker", ["ps", "--format", "{{.Names}}"], stderr_to_stdout: true)
    String.contains?(output, @container_name)
  rescue
    _ -> false
  end

  @doc "Get the SSH key path for the test container."
  def key_path do
    Path.join([docker_dir(), ".keys", "test_key"])
  end

  @doc "Get the test target for connecting to the Docker container."
  def target do
    %Fusion.Target{
      host: "localhost",
      port: @ssh_port,
      username: @username,
      auth: {:key, key_path()}
    }
  end

  @doc "Get a password-based target for the Docker container."
  def target_password do
    %Fusion.Target{
      host: "localhost",
      port: @ssh_port,
      username: @username,
      auth: {:password, @password}
    }
  end

  @doc "Check if Docker and the test container are available."
  def available? do
    container_running?() and File.exists?(key_path())
  end

  @doc "Verify SSH connectivity to the container."
  def ssh_works? do
    {_output, exit_code} =
      System.cmd(
        "ssh",
        [
          "-i",
          key_path(),
          "-p",
          to_string(@ssh_port),
          "-o",
          "BatchMode=yes",
          "-o",
          "StrictHostKeyChecking=no",
          "-o",
          "ConnectTimeout=5",
          "#{@username}@localhost",
          "echo",
          "ok"
        ],
        stderr_to_stdout: true
      )

    exit_code == 0
  rescue
    _ -> false
  end

  defp docker_dir do
    Path.join([File.cwd!(), "test", "docker"])
  end
end
