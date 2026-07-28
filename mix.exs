defmodule Slab.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/chrislaskey/slab"

  def project do
    [
      app: :slab,
      version: @version,
      elixir: "~> 1.15",
      # Extracts colocated hooks (phoenix-colocated/slab)
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Slab",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_select, "~> 1.0"},
      {:plug, "~> 1.14"},
      {:ecto, "~> 3.0", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A data table component for Phoenix LiveView with URL-driven sorting, " <>
      "row selection, and automatic cell rendering based on Ecto schema types."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE.md)
    ]
  end

  defp docs do
    [
      main: "Slab",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
