defmodule Mix.Tasks.Nerves.System.Gen.Pkg do
  use Mix.Task
  require Logger

  alias Nerves.System.Squashfs

  @exclude ~w(skeleton toolchain linux)
  @deps_exclude ~w(skeleton-undefined toolchain-virtual)

  @moduledoc """
    Export Nerves System Packages
  """

  @dir "nerves/system"

  def run(_args) do
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
    |> IO.inspect

    gen_pkgs(rootfs, pkg_manifests, tuple)
  end

  def gen_pkgs(rootfs, pkg_manifests, tuple) do
    {:ok, pid} = Squashfs.start_link(rootfs)
      File.ls!(pkg_manifests)
      |> Enum.filter(& !&1 in @exclude)
      |> Enum.map(&manifest_path/1)
      |> Enum.map(&parse_manifest/1)
      |> Enum.filter(& Keyword.get(&1, :files, []) != [])
      |> Enum.map(&clean_deps/1)
      |> Enum.map(& gen_fs(&1, pid, tuple))
      |> Enum.map(& gen_pkg(&1, tuple))
    Squashfs.stop(pid)
  end

  def clean_deps(manifest) do
    deps =
      (manifest[:dependencies] || [])
      |> Enum.reject(& &1 in @deps_exclude)
      |> Enum.reject(& String.starts_with?(&1, "host-"))
      |> Enum.map(fn(dep) ->
        dep
        |> String.reverse
        |> String.split("-", parts: 2)
        |> Enum.map(&String.reverse/1)
        |> Enum.reverse
        |> List.to_tuple
      end)
    Keyword.put(manifest, :dependencies, deps)
  end

  def gen_fs(manifest, pid, tuple) do
    system_files = Squashfs.files(pid)
    files = manifest[:files] || []

    name = manifest[:name]
    {target, staging} =
      files
      |> Enum.partition(fn(file) ->
        file in system_files
      end)

    fs_path =
      File.cwd!
      |> Path.join("pkg")
      |> Path.join("#{name}-#{tuple}.squashfs")

    Squashfs.fragment(pid, target, fs_path, name: "#{name}-pseudofile")

    staging_dest_path =
      File.cwd!
      |> Path.join("pkg")
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
    if staging != [] do
      staging_tar =
        File.cwd!
        |> Path.join("pkg")
        |> Path.join("#{name}-#{tuple}.staging.tar.gz")
        |> String.to_char_list
      :erl_tar.create(staging_tar, staging_file_list, [:compressed])
    end


    manifest
    |> Keyword.put(:fs_overlay, fs_path)
    |> Keyword.put(:staging_overlay, staging_tar)
  end

  def gen_pkg(manifest, tuple) do
    #IO.inspect manifest
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

end
