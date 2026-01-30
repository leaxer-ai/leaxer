defmodule LeaxerCore.NativeLauncher.Unix do
  @moduledoc """
  Unix-specific (Linux/macOS) native binary launcher.

  On Unix systems, library loading works correctly via environment variables:
  - Linux: `LD_LIBRARY_PATH`
  - macOS: `DYLD_LIBRARY_PATH`

  This module provides the same interface as the Windows launcher but uses
  standard Port.open with properly configured environment variables.
  """

  require Logger

  @doc """
  Spawn a native executable with proper library path setup.

  Sets LD_LIBRARY_PATH (Linux) or DYLD_LIBRARY_PATH (macOS) to include bin_dir.
  """
  @spec spawn_executable(String.t(), [String.t()], keyword()) ::
          {:ok, port(), non_neg_integer() | nil} | {:error, term()}
  def spawn_executable(exe_path, args, opts \\ []) do
    bin_dir = Keyword.get(opts, :bin_dir, "")
    cd = Keyword.get(opts, :cd, bin_dir)
    additional_env = Keyword.get(opts, :env, [])
    extra_port_opts = Keyword.get(opts, :port_opts, [])

    # Build environment
    env = build_process_env(bin_dir, additional_env)

    # Port options
    base_port_opts = [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: args,
      env: env
    ]

    # Add cd option if specified
    port_opts =
      if cd && cd != "" do
        base_port_opts ++ [cd: cd]
      else
        base_port_opts
      end

    port_opts = port_opts ++ extra_port_opts

    Logger.debug("[NativeLauncher.Unix] Spawning: #{exe_path} #{Enum.join(args, " ")}")

    try do
      port = Port.open({:spawn_executable, exe_path}, port_opts)

      os_pid =
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
          _ -> nil
        end

      Logger.info("[NativeLauncher.Unix] Spawned process with OS PID: #{inspect(os_pid)}")

      {:ok, port, os_pid}
    rescue
      e ->
        Logger.error("[NativeLauncher.Unix] Failed to spawn: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Build environment variables for a Unix child process.

  Sets LD_LIBRARY_PATH (Linux) or DYLD_LIBRARY_PATH (macOS) to include bin_dir.
  Inherits all parent environment variables.
  """
  @spec build_process_env(String.t(), [{String.t(), String.t()}]) :: [{charlist(), charlist()}]
  def build_process_env(bin_dir, additional_env \\ []) do
    # Start with all current environment variables
    base_env =
      System.get_env()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    # Determine which library path variable to use based on OS
    {lib_path_var, lib_path_charlist} = library_path_var()

    # Get current library path and prepend bin_dir
    current_lib_path = System.get_env(lib_path_var) || ""
    new_lib_path = if current_lib_path == "", do: bin_dir, else: "#{bin_dir}:#{current_lib_path}"

    # Build final environment
    base_env
    |> Enum.reject(fn {k, _} -> k == lib_path_charlist end)
    |> Kernel.++([
      {lib_path_charlist, String.to_charlist(new_lib_path)},
      {~c"GGML_BACKEND_DIR", String.to_charlist(bin_dir)}
    ])
    |> Kernel.++(
      Enum.map(additional_env, fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)
    )
  end

  # Determine the library path environment variable for the current OS
  defp library_path_var do
    case :os.type() do
      {:unix, :darwin} -> {"DYLD_LIBRARY_PATH", ~c"DYLD_LIBRARY_PATH"}
      _ -> {"LD_LIBRARY_PATH", ~c"LD_LIBRARY_PATH"}
    end
  end
end
