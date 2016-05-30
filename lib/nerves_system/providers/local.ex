defmodule Nerves.System.Providers.Local do
  use Nerves.System.Provider
  alias Nerves.Env
  alias Nerves.System.{Platform, Providers}
  alias Nerves.System.Providers.Local.Stream, as: OutStream

  @buildroot_cache "~/.nerves/cache/buildroot"
  @system_cache "~/.nerves/cache/system"

  require Logger

  def cache_get(system, version, config, _dest) do
    shell_info "Checking Cache for #{system}-#{version}"
    cache_dir = system_cache_dir

    system_path =
      cache_dir
      |> Path.join("#{system}-#{version}")
    case File.dir?(system_path) do
      true ->
        System.put_env("NERVES_SYSTEM", system_path)
        shell_info "Found cached system"
        {:ok, system_path}
      false ->
        output = """
        #{system}-#{version} was not found in your cache.
        cache dir: #{cache_dir}
        """
        [IO.ANSI.yellow, output, IO.ANSI.reset]
        |> Mix.shell.info
        "Would you like to download the system to your cache?"
        |> Mix.shell.yes?
        |> cache_fetch(system, version, config, system_path)
    end
  end

  def compile(system, config, dest) do
    {_, type} = :os.type
    compile(type, system, config, dest)
  end

  def compile(:linux, _system, _config, dest) do
    # TODO: Perform a platform check
    Application.put_env(:porcelain, :driver, Porcelain.Driver.Basic)
    Application.ensure_all_started(:porcelain)
    # Find the build platform dep
    # Call out to the command to create a build
    #  #{build_platform}/create_build.sh #{config_dir} #{destination}
    File.mkdir_p!(dest)
    File.mkdir_p(Path.expand(@buildroot_cache))

    system = Env.system
    build_platform = system.config[:build_platform] || Nerves.System.BR

    bootstrap(build_platform, system, dest)
    build(build_platform, system, dest)
  end

  def compile(type, _, _, _) do
    {:error, """
    Local compiler support is not available for your host: #{type} it is only available on linux
    """}
  end

  defp cache_fetch(false, _, _, _, _), do: Mix.raise "Unable to set NERVES_SYSTEM"
  defp cache_fetch(true, system, version, config, dest) do
    case Providers.Http.cache_get(system, version, config, dest) do
      {:ok, _} ->
        System.put_env("NERVES_SYSTEM", dest)
        {:ok, dest}
      error -> error
    end
  end

  defp bootstrap(Nerves.System.Platforms.BR, %Env.Dep{} = system, dest) do
    cmd = Path.join(Env.dep(:nerves_system_br).path, "create-build.sh")
    build_config = Platform.build_config(system)
    config_dir = Path.join(dest, build_config[:dest])
    shell! "#{cmd} #{Path.join(config_dir, build_config[:defconfig])} #{dest}"
  end

  defp build(Nerves.System.Platforms.BR, _system, dest) do
    shell! "make", dir: dest
  end

  defp shell!(cmd, opts \\ []) do
    in_stream = IO.binstream(:standard_io, :line)
    {:ok, pid} = OutStream.start_link(file: Path.join(File.cwd!, "build.log"))
    out_stream = IO.stream(pid, :line)
    %{status: 0} = Porcelain.shell(cmd, [in: in_stream, async_in: true, out: out_stream, err: :out] ++ opts)
  end

  defp shell_info(text) do
    Provider.shell_info "[local] #{text}"
  end

  def system_cache_dir do
    System.get_env("NERVES_SYSTEM_CACHE_DIR") || Path.expand(@system_cache)
  end
end
