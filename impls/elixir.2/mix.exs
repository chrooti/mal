defmodule Mal.MixProject do
  use Mix.Project

  def project do
    [
      app: :mal,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        flags: ["-Wextra_return", "-Wmissing_return", "-Wunderspecs", "-Wunmatched_returns"],
        plt_add_apps: [:iex]
      ]
    ]
  end

  def application do
    [
      mod: {Mal, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "credo",
        "dialyzer"
      ]
    ]
  end
end
