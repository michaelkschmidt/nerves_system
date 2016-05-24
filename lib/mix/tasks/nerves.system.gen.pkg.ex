defmodule Mix.Tasks.Nerves.System.Gen.Pkg do
  use Mix.Task
  require Logger

  alias Nerves.System.Squashfs

  @exclude ~w(skeleton toolchain linux toolchain-external)

  @moduledoc """
    Generate Nerves System Packages
  """

  @dir "nerves/system"
  @output_dir File.cwd! |> Path.join("pkg")
  @switches []

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
        Mix.Task.run "help", ["nerves.system.gen.pkg"]
      [path|_] ->
        File.rm_rf(path)
        File.mkdir_p(path)
        run(path, opts)
    end
  end

  def run(path, _opts) do
    Nerves.Env.initialize
    system_path =
      Mix.Project.build_path
      |> Path.join(@dir)

    rootfs =
      system_path
      |> Path.join("images")
      |> Path.join("rootfs.squashfs")

    pkg_manifests =
      system_path
      |> Path.join("build")
      |> Path.join("pkg-manifest")

    unless File.exists?(rootfs) do
      Mix.raise "Not a valid Root FS"
    end

    unless File.dir?(pkg_manifests) do
      Mix.raise "Could not load manifests at: #{pkg_manifests}"
    end
    toolchain = Nerves.Env.toolchain.app
    Application.ensure_started(toolchain)
    tuple = Application.get_env(toolchain, :target_tuple)

    gen_pkgs(rootfs, pkg_manifests, tuple, path)
  end

  def gen_pkgs(rootfs, pkg_manifests, tuple, path) do
    {:ok, pid} = Squashfs.start_link(rootfs)
    {rejected_pkgs, pkgs} =
      File.ls!(pkg_manifests)
      |> Enum.map(&manifest_path/1)
      |> Enum.map(&parse_manifest/1)
      |> Enum.reduce({[], []}, fn(manifest, {r, k}) ->
        cond do
          (manifest[:name] in @exclude) ->
            {[{manifest, "Excluded"} | r], k}
          (Keyword.get(manifest, :files, []) == []) ->
            {[{manifest, "No Filesystem"} | r], k}
          (Version.parse(manifest[:version]) == :error) ->
            {[{manifest, "Incompatable version: #{manifest[:version]}"} | r], k}
          (Enum.any?(manifest[:dependencies], fn({dep, vsn}) ->
            Version.parse(vsn) == :error
          end)) -> {[{manifest, "Incompatable dependency version: #{inspect manifest[:dependencies]}"} | r], k}
          true -> {r, [manifest | k]}
        end
      end)
    pkgs
      |> Enum.map(& gen_fs(&1, pid, tuple, path))
      |> Enum.each(& gen_pkg(&1, tuple, path))

    Squashfs.stop(pid)

    rejected_pkgs =
      rejected_pkgs
      |> Enum.map(fn({manifest, reason}) ->
        """
        #{manifest[:name]} rejected for reason: #{reason}
        """
      end)
    if rejected_pkgs != [] do
      output = """

      Rejected Packages
      -----------------
      #{Enum.join(rejected_pkgs, "")}
      """
      Mix.shell.info([IO.ANSI.yellow, output, IO.ANSI.reset])
    end
    gen_pkgs =
      pkgs
      |> Enum.map(fn(manifest) ->
        """
        #{manifest[:name]}-#{manifest[:version]}
        """
      end)
    output = """

    Generated Packages
    -----------------
    #{Enum.join(gen_pkgs, "")}
    """
    Mix.shell.info([IO.ANSI.green, output, IO.ANSI.reset])
  end

  def gen_fs(manifest, pid, tuple, path) do
    system_files = Squashfs.files(pid)
    files = manifest[:files] || []

    name = manifest[:name]
    {target, staging} =
      files
      |> Enum.partition(fn(file) ->
        file in system_files
      end)

    fs_path =
      path
      |> Path.join("#{name}-#{tuple}.squashfs")

    Squashfs.fragment(pid, target, fs_path, name: "#{name}-#{tuple}.pseudofile")

    staging_dest_path =
      path
      |> Path.join("#{name}-staging")

    staging_src_path =
      Mix.Project.build_path
      |> Path.join(@dir)
      |> Path.join("staging")

    staging_file_list =
      staging
      |> Enum.reduce([], fn(file, acc) ->
        src = Path.join(staging_src_path, file)
        dest = Path.join(staging_dest_path, file)
        case File.exists?(src) do
          true ->
            archive_file =
              Path.join("staging", file)
              |> String.to_char_list()
            [{archive_file, String.to_char_list(dest)}]
          false ->
            acc
        end
      end)
    staging_tar =
      if staging != [] do
        tar =
          path
          |> Path.join("#{name}-#{tuple}.staging.tar.gz")
          |> String.to_char_list
        :erl_tar.create(tar, staging_file_list, [:compressed])
        tar
      end
    manifest
    |> Keyword.put(:fs_overlay, fs_path)
    |> Keyword.put(:staging_overlay, staging_tar)
  end

  def gen_pkg(manifest, tuple, path) do

    deps =
      Keyword.get(manifest, :dependencies, [])
      |> Enum.flat_map(fn({dep, vsn}) -> ["--dep", "#{dep}-#{vsn}"] end)

    licenses =
      Keyword.get(manifest, :license, [])
      |> Enum.flat_map(&["--license", &1])

    version = parse_version(manifest[:version])

    path =
      path
      |> Path.join(manifest[:name])
    Mix.Task.reenable "nerves.system.pkg.new"
    Mix.Task.run "nerves.system.pkg.new", [path, "--version", version] ++ deps ++ licenses
  end

  def manifest_path(manifest) do
    Mix.Project.build_path
    |> Path.join(@dir)
    |> Path.join("build")
    |> Path.join("pkg-manifest")
    |> Path.join(manifest)
  end

  def parse_manifest(manifest) do
    File.read!(manifest)
    |> String.split("\n")
    |> parse_manifest_lines
    |> parse_manifest_vsn
    |> parse_manifest_deps
    |> normalize
  end

  defp parse_manifest_lines(_, _ \\ [])
  defp parse_manifest_lines([], collection), do: collection
  defp parse_manifest_lines(["" | tail], collection), do: parse_manifest_lines(tail, collection)
  defp parse_manifest_lines([line | tail], collection) do
    [key, value] = String.split(line, ",", parts: 2)
    collection =
      if value != "" do
        collection = update_manifest_collection(String.to_atom(key), value, collection)
      else
        collection
      end
    parse_manifest_lines(tail, collection)
  end


  defp parse_version(vsn), do: vsn

  defp update_manifest_collection(:installed, <<".", file :: binary>>, collection) do
    files = Keyword.get(collection, :files, [])
    Keyword.put(collection, :files, [file | files])
  end

  defp update_manifest_collection(:license, value, collection) do
    licenses =
      value
      |> String.split(",")
      |> Enum.map(&String.strip/1)
    Keyword.put(collection, :license, licenses)
  end

  defp update_manifest_collection(:dependencies, value, collection) do
    dependencies =
      value
      |> String.split(" ")
      |> Enum.map(&String.strip/1)
    Keyword.put(collection, :dependencies, dependencies)
  end

  defp update_manifest_collection(key, value, collection) when key in [:name, :version, :url] do
    Keyword.put(collection, key, String.strip(value))
  end

  defp parse_manifest_vsn(manifest) do
    vsn =
      manifest[:version]
      |> convert_vsn
    Keyword.put(manifest, :version, vsn)
  end

  defp convert_vsn(<<"v", vsn :: binary>>), do: convert_vsn(vsn)
  defp convert_vsn(vsn) when is_binary(vsn) do
    case Version.parse(vsn) do
      {:ok, _} -> vsn
      _ ->
        String.split(vsn, ".")
        |> convert_vsn
    end
  end

  defp convert_vsn([binary]), do: binary
  defp convert_vsn([m | [mi | []]]), do: "#{m}.#{mi}.0"
  defp convert_vsn([_ | [_ | [_ | []]]] = vsn) do
    [h | t] = Enum.reverse(vsn)
    case Integer.parse(h) do
      {int, ""} ->
        ["#{int}" | t]
      {int, rest} ->
        ["#{int}-#{rest}" | t]
        |> Enum.reverse
        |> Enum.join(".")
      _ ->
        vsn
        |> Enum.reverse
        |> Enum.join(".")
    end
  end
  defp convert_vsn(vsn), do: vsn

  defp parse_manifest_deps(manifest) do
    deps =
      (manifest[:dependencies] || [])
      |> Enum.reject(& String.starts_with?(&1, "host-"))
      |> Enum.map(&convert_dep/1)
      |> Enum.reject(fn({dep, vsn}) -> dep in @exclude or vsn == "virtual" end)
    Keyword.put(manifest, :dependencies, deps)
  end

  defp convert_dep(dep) do
    {dep, vsn} =
      dep
      |> String.reverse
      |> String.split("-", parts: 2)
      |> Enum.map(&String.reverse/1)
      |> Enum.reverse
      |> List.to_tuple
    {String.replace(dep, "-", "_"), convert_vsn(vsn)}
  end

  defp normalize(manifest) do
    Keyword.put(manifest, :name, String.replace(manifest[:name], "-", "_"))
  end

  defp switch_to_string({name, nil}), do: name
  defp switch_to_string({name, val}), do: name <> "=" <> val
end
