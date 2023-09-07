defmodule Stoker.MixProject do
  use Mix.Project

  @source_url "https://github.com/l3nz/stoker"
  # "0.1.0-dev"
  @version "0.1.3"

  def project do
    [
      app: :stoker,
      version: @version,
      description: "Stoker makes sure your cluster keeps running",
      package: package(),
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:say_cheez_ex, "~> 0.3"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}

      {:local_cluster, "~> 1.2", only: [:test]},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["lenz"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib)
    ]
  end
end
