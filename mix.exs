defmodule Fusion.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/elpddev/fusion"

  def project do
    [
      app: :fusion,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description:
        "Remote task runner using Erlang distribution over SSH. Push modules and execute functions on remote machines without pre-installing your application. Zero dependencies.",
      package: package(),
      source_url: @source_url,

      # Docs
      name: "Fusion",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh, :public_key, :crypto],
      mod: {Fusion.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/helpers"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
