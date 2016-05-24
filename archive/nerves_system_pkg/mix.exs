defmodule NervesSysPkg.Mixfile do
  use Mix.Project

  def project do
    [app: :nerves_sys_pkg,
     version: "0.0.1",
     elixir: "~> 1.2.4 or ~> 1.3-dev",
     aliases: aliases]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  def aliases do
    [install: ["archive.build -o nerves_system_pkg.ez", "archive.install nerves_system_pkg.ez --force"]]
  end
end
