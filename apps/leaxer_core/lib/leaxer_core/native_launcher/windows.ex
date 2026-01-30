defmodule LeaxerCore.NativeLauncher.Windows do
  @moduledoc """
  Windows-specific native binary launcher with proper DLL search path setup.

  Uses PowerShell with `-WindowStyle Hidden` to launch executables without
  showing a console window, while ensuring the working directory is set BEFORE
  the executable is spawned (required for Windows DLL loading).

  ## The Problem

  Windows DLL loader resolves dependencies during `CreateProcess`, BEFORE the
  child process starts. The `cd:` option in `Port.open` sets the working directory
  for the child process AFTER it starts. This means DLL resolution happens using
  the parent process's (BEAM VM) current directory, not the bin directory.

  ## The Solution

  Use PowerShell with:
  1. `-WindowStyle Hidden` - No visible console window
  2. `Set-Location` - Change directory before spawning
  3. `& 'exe'` - Execute the binary with proper argument handling

  This works because PowerShell changes the working directory before the
  executable is spawned, and the hidden window style prevents console flash.
  """

  require Logger

  @spec spawn_executable(String.t(), [String.t()], keyword()) ::
          {:ok, port(), non_neg_integer() | nil} | {:error, term()}
  def spawn_executable(exe_path, args, opts \\ []) do
    bin_dir = Keyword.get(opts, :bin_dir) || Path.dirname(exe_path)
    additional_env = Keyword.get(opts, :env, [])
    extra_port_opts = Keyword.get(opts, :port_opts, [])

    # Convert to Windows-style paths
    native_bin_dir = to_windows_path(bin_dir)
    native_exe_path = to_windows_path(exe_path)

    Logger.debug("[NativeLauncher.Windows] Spawning: #{native_exe_path}")
    Logger.debug("[NativeLauncher.Windows] DLL dir: #{native_bin_dir}")

    spawn_via_powershell(native_exe_path, args, native_bin_dir, additional_env, extra_port_opts)
  end

  defp spawn_via_powershell(exe_path, args, bin_dir, additional_env, extra_port_opts) do
    # Pre-spawn DLL validation for better error diagnostics
    validate_dll_presence(bin_dir)

    env = build_process_env(bin_dir, additional_env)
    escaped_args = Enum.map(args, &escape_powershell_arg/1) |> Enum.join(" ")

    # PowerShell command: change directory then run executable
    # Using single quotes for paths to avoid variable expansion issues
    ps_command = "Set-Location -LiteralPath '#{escape_ps_string(bin_dir)}'; & '#{escape_ps_string(exe_path)}' #{escaped_args}"

    # Log full PowerShell command for debugging
    Logger.debug("[NativeLauncher.Windows] Full PowerShell command: #{ps_command}")

    # Log PATH environment variable
    {_, path_value} =
      Enum.find(env, {nil, ~c""}, fn {k, _} -> k == ~c"PATH" end)

    path_str = to_string(path_value)
    # Only log first portion of PATH to avoid excessive logging
    path_preview = String.slice(path_str, 0, 500)
    Logger.debug("[NativeLauncher.Windows] PATH env (first 500 chars): #{path_preview}")

    powershell_exe =
      System.find_executable("powershell.exe") ||
        "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"

    port_opts =
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [
          "-WindowStyle",
          "Hidden",
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-Command",
          ps_command
        ],
        env: env
      ] ++ extra_port_opts

    try do
      port = Port.open({:spawn_executable, powershell_exe}, port_opts)

      os_pid =
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
          _ -> nil
        end

      Logger.info("[NativeLauncher.Windows] Spawned via PowerShell (hidden), OS PID: #{inspect(os_pid)}")
      {:ok, port, os_pid}
    rescue
      e ->
        Logger.error("[NativeLauncher.Windows] Failed to spawn: #{inspect(e)}")
        {:error, e}
    end
  end

  # Validate that required DLLs are present in the bin directory
  # This provides clear error messages when DLLs are missing
  defp validate_dll_presence(bin_dir) do
    # Critical DLLs for llama.cpp - llama.dll is the main one
    critical_dlls = ["llama.dll"]

    # CUDA-related DLLs (optional but logged if missing when CUDA is expected)
    cuda_dlls = ["ggml-cuda.dll", "cublas64_12.dll", "cublasLt64_12.dll", "cudart64_12.dll"]

    # Check critical DLLs
    Enum.each(critical_dlls, fn dll ->
      dll_path = Path.join(bin_dir, dll)

      if File.exists?(dll_path) do
        Logger.debug("[NativeLauncher.Windows] Found critical DLL: #{dll}")
      else
        Logger.error(
          "[NativeLauncher.Windows] CRITICAL: #{dll} not found at #{dll_path}"
        )

        # Log directory contents to help diagnose the issue
        case File.ls(bin_dir) do
          {:ok, files} ->
            Logger.error(
              "[NativeLauncher.Windows] bin_dir contents: #{inspect(Enum.take(files, 20))}"
            )

          {:error, reason} ->
            Logger.error(
              "[NativeLauncher.Windows] Cannot list bin_dir #{bin_dir}: #{inspect(reason)}"
            )
        end
      end
    end)

    # Log CUDA DLL status (not critical, just informational)
    cuda_present =
      Enum.filter(cuda_dlls, fn dll ->
        File.exists?(Path.join(bin_dir, dll))
      end)

    cuda_missing =
      Enum.reject(cuda_dlls, fn dll ->
        File.exists?(Path.join(bin_dir, dll))
      end)

    if cuda_present != [] do
      Logger.info("[NativeLauncher.Windows] CUDA DLLs present: #{inspect(cuda_present)}")
    end

    if cuda_missing != [] do
      Logger.debug("[NativeLauncher.Windows] CUDA DLLs not found (may be expected for CPU-only): #{inspect(cuda_missing)}")
    end
  end

  # Escape argument for PowerShell command line
  # PowerShell uses backtick (`) as escape character and requires special handling
  defp escape_powershell_arg(arg) when is_binary(arg) do
    if needs_ps_quoting?(arg) do
      # Escape embedded single quotes by doubling them
      escaped = String.replace(arg, "'", "''")
      "'#{escaped}'"
    else
      arg
    end
  end

  # Check if argument needs quoting for PowerShell
  defp needs_ps_quoting?(arg) do
    String.contains?(arg, [" ", "\t", "'", "\"", "&", "|", "<", ">", "(", ")", "{", "}", "$", "`", ";"])
  end

  # Escape string for use inside PowerShell single quotes
  defp escape_ps_string(str) do
    String.replace(str, "'", "''")
  end

  @doc """
  Build environment variables for a Windows child process.

  Prepends bin_dir to PATH and sets GGML_BACKEND_DIR for CUDA backend discovery.
  """
  @spec build_process_env(String.t(), [{String.t(), String.t()}]) :: [{charlist(), charlist()}]
  def build_process_env(bin_dir, additional_env \\ []) do
    base_env =
      System.get_env()
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    current_path = System.get_env("PATH") || ""
    new_path = "#{bin_dir};#{current_path}"

    base_env
    |> Enum.reject(fn {k, _} -> k == ~c"PATH" end)
    |> Kernel.++([
      {~c"PATH", String.to_charlist(new_path)},
      {~c"GGML_BACKEND_DIR", String.to_charlist(bin_dir)}
    ])
    |> Kernel.++(
      Enum.map(additional_env, fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)
    )
  end

  defp to_windows_path(path) when is_binary(path), do: String.replace(path, "/", "\\")
  defp to_windows_path(nil), do: nil
end
