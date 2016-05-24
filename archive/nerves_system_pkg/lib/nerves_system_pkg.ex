defmodule Mix.Tasks.Nerves.System.Pkg.New do
  use Mix.Task
  import Mix.Generator


  @shortdoc "Creates a new Nerves System Pkg"
  @new [
    {:eex,  "mix.exs",     "mix.exs"},
    {:eex,  "nerves.exs",  "nerves.exs"},
    {:eex,  "README.md",   "README.md"},
    {:eex,  "VERSION",      "VERSION"}
  ]

  # Embed all defined templates
  root = Path.expand("../template", __DIR__)

  for {format, source, _} <- @new do
    unless format == :keep do
      @external_resource Path.join(root, source)
      def render(unquote(source)), do: unquote(File.read!(Path.join(root, source)))
    end
  end

  @switches [version: :string, dep: :keep, license: :keep]
  def run(argv) do
    {opts, argv} =
      case OptionParser.parse(argv, strict: @switches) do
        {opts, argv, []} ->
          {opts, argv}
        {_opts, _argv, [switch | _]} ->
          Mix.raise "Invalid option: " <> switch_to_string(switch)
      end

    case argv do
      [] ->
        Mix.Task.run "help", ["nerves.system.pkg"]
      [path|_] ->
        app = opts[:app] || Path.basename(Path.expand(path))
        check_application_name!(app, !!opts[:app])
        mod = opts[:module] || Macro.camelize(app)
        check_module_name_validity!(mod)
        check_module_name_availability!(mod)

        run(app, mod, path, opts)
    end
  end

  def run(app, mod, path, opts) do
    vsn = opts[:version]
    deps = parse_deps(opts)
    licenses = parse_licenses(opts)


    binding = [application_name: app,
               application_module: mod,
               application_vsn: vsn,
               application_licenses: licenses,
               application_deps: deps]

    copy_from path, binding, @new
  end

  defp parse_deps(opts) do
    opts
    |> Keyword.get_values(:dep)
    |> Enum.map(fn(dep) ->
      dep
      |> String.split("-", parts: 2)
      |> List.to_tuple
    end)
  end

  defp parse_licenses(opts) do
    opts
    |> Keyword.get_values(:license)
  end

  defp switch_to_string({name, nil}), do: name
  defp switch_to_string({name, val}), do: name <> "=" <> val

  defp check_application_name!(name, from_app_flag) do
    unless name =~ ~r/^[a-z][\w_]*$/ do
      extra =
        if !from_app_flag do
          ". The application name is inferred from the path, if you'd like to " <>
          "explicitly name the application then use the `--app APP` option."
        else
          ""
        end

      Mix.raise "Application name must start with a letter and have only lowercase " <>
                "letters, numbers and underscore, got: #{inspect name}" <> extra
    end
  end

  defp check_module_name_validity!(name) do
    unless name =~ ~r/^[A-Z]\w*(\.[A-Z]\w*)*$/ do
      Mix.raise "Module name must be a valid Elixir alias (for example: Foo.Bar), got: #{inspect name}"
    end
  end

  defp check_module_name_availability!(name) do
    name = Module.concat(Elixir, name)
    if Code.ensure_loaded?(name) do
      Mix.raise "Module name #{inspect name} is already taken, please choose another name"
    end
  end

  defp copy_from(target_dir, binding, mapping) when is_list(mapping) do
    application_name = Keyword.fetch!(binding, :application_name)
    for {format, source, target_path} <- mapping do
      target = Path.join(target_dir,
                         String.replace(target_path, "application_name", application_name))

      case format do
        :keep ->
          File.mkdir_p!(target)
        :text ->
          create_file(target, render(source))
        :append ->
          append_to(Path.dirname(target), Path.basename(target), render(source))
        :eex  ->
          contents = EEx.eval_string(render(source), binding, file: source)
          create_file(target, contents)
      end
    end
  end

  defp append_to(path, file, contents) do
    file = Path.join(path, file)
    File.write!(file, File.read!(file) <> contents)
  end
end
