defmodule Nerves.System.Providers.Http do
  use Nerves.System.Provider

  @recv_timeout 120_000

  def cache_get(_system, _version, config, destination) do
    shell_info "Downloading System"
    config[:mirrors]
    |> get
    |> unpack(destination)
  end

  def compile(_system, _config, _dest) do
    {:error, :nocompile}
  end

  defp get([mirror | mirrors]) do
    mirror
    |> URI.encode
    |> String.replace("+", "%2B")
    |> Mix.Utils.read_path()
    |> result(mirrors)
  end

  defp result({:ok, body}, _) do
    shell_info "System Downloaded"
    {:ok, body}
  end
  defp result(_, []) do
    shell_info "No Available Locations"
    {:error, :nocache}
  end
  defp result(_, mirrors) do
    shell_info "Switching Location"
    get(mirrors)
  end

  defp unpack({:error, _} = error, _), do: error
  defp unpack({:ok, tar}, destination) do
    shell_info "Unpacking System"
    tmp_path = Path.join(destination, ".tmp")
    File.mkdir_p!(tmp_path)
    tar_file = Path.join(tmp_path, "system.tar.xz")
    File.write(tar_file, tar)

    extract_archive("system.tar.xz",tmp_path)
    source =
      File.ls!(tmp_path)
      |> Enum.map(& Path.join(tmp_path, &1))
      |> Enum.find(&File.dir?/1)

    File.rm!(tar_file)
    File.cp_r(source, destination)
    File.rm_rf!(tmp_path)
    {:ok, destination}
  end

  defp extract_archive(tar_file,tmp_dir) do
    {_,os_type} = :os.type
    extract_archive(os_type,tar_file,tmp_dir)
  end

  defp extract_archive(:nt,tarxz_file,tmp_dir) do
    System.cmd("7z", ["x", tarxz_file], cd: tmp_dir)
    tar_file = String.replace_suffix(tarxz_file,".xz","")
    System.cmd("7z", ["x", tar_file], cd: tmp_dir)
  end

  defp extract_archive(_,tar_file,tmp_dir) do
    System.cmd("tar", ["xf", tar_file], cd: tmp_dir)
  end


  defp shell_info(text) do
    Provider.shell_info "[http] #{text}"
  end
end
