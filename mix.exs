defmodule Translate.Mixfile do
  use Mix.Project

  def project do
    [ app: :translate,
      version: "0.0.1",
      elixir: "~> 1.0.0",
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
    [ {:ibrowse, github: "cmullaparthi/ibrowse", tag: "v4.1.0"},
      {:httpotion, "~> 0.2.0"},
      {:jsx, "2.1.1" } ]
  end
end
