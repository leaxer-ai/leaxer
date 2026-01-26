defmodule Leaxer.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      # Only Elixir apps - leaxer_ui and leaxer_desktop are Node.js/Tauri
      apps: [:leaxer_core],
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: releases()
    ]
  end

  defp releases do
    [
      leaxer_core: [
        include_erts: true,
        include_executables_for: [:windows, :unix],
        applications: [
          leaxer_core: :permanent,
          runtime_tools: :permanent
        ],
        strip_beams: true
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end
end
