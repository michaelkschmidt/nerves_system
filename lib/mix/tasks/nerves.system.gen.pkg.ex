defmodule Mix.Tasks.Nerves.System.Gen.Pkg do
  use Mix.Task
  require Logger

  alias Nerves.System.Squashfs

  @exclude ~w(skeleton toolchain)
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

    gen_pkgs(rootfs, pkg_manifests)
  end

  def gen_pkgs(rootfs, pkg_manifests) do
    {:ok, pid} = Squashfs.start_link(rootfs)
      File.ls!(pkg_manifests)
      |> Enum.filter(& !&1 in @exclude)
      |> Enum.map(&manifest_path/1)
      |> Enum.map(&parse_manifest/1)
      |> Enum.filter(& Keyword.get(&1, :files, []) != [])
      |> Enum.each(& gen_pkg(&1, pid))
    Squashfs.stop(pid)
  end

  def gen_pkg(manifest, pid) do
    system_files = Squashfs.files(pid)
    files = manifest[:files] || []

    name = manifest[:name]
    {target, staging} =
      files
      |> Enum.partition(fn(file) ->
        file in system_files
      end)

    path =
      File.cwd!
      |> Path.join("pkg")
      |> Path.join(name <> ".squashfs")

    Squashfs.fragment(pid, target, path)
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
