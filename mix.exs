defmodule Translate.Mixfile do
  use Mix.Project

  def project do
    [ app: :translate,
      version: "0.0.3",
      elixir: "~> 1.1.1",
      escript: [ main_module: Main ],
      deps: deps ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [ applications: [ :logger, :httpotion ] ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [ {:ibrowse, "~> 4.2.2" },
      {:httpotion, "~> 2.1.0"},
      {:jsx, "~> 2.8.0" } ]
  end
end
