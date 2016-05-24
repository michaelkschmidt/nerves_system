defmodule <%= application_module %>.Mixfile do
  use Mix.Project

  @version Path.join(__DIR__, "VERSION")
    |> File.read!
    |> String.strip

  def project do
    [app: :<%= application_name %>,
     version: @version,
     compilers: [:app],
     description: description,
     package: package,
     deps: deps]
  end

  def application do
    []
  end

  def deps do
    [<%= for {dep, vsn} <- application_deps do %>{:<%= dep %>, "~> <%= vsn %>"},<% end %>]
  end

  defp description do
    """
    Nerves System Package: <%= application_name %>
    These packages are automatically generated
    """
  end

  defp package do
    [maintainers: ["Frank Hunleth", "Justin Schneck"],
     licenses: [<%= for l <- application_licenses do %>"<%= l %>",<% end %>],
     files: ["mix.exs", "nerves.exs", "VERSION", "README.md"]]
  end

end
