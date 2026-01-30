defmodule LeaxerCore.NativeLauncher do
  @moduledoc """
  Platform-specific native binary launcher for Windows DLL loading compatibility.

  This module solves the Windows DLL loading issue where Erlang's `Port.open` fails
  to properly inherit DLL search paths. On Windows, the DLL loader uses a specific
  search order that doesn't work well with how Erlang spawns child processes.

  ## The Problem

  On Windows, when `Port.open` spawns a process via `CreateProcess`, the child
  process cannot find DLLs (CUDA, llama.dll, etc.) even when they exist in the
  same directory as the executable. This results in error code -1073741515
  (STATUS_DLL_NOT_FOUND).

  ## The Solution

  - **Windows**: Use PowerShell to call `SetDllDirectory()` Win32 API before
    spawning the process. This ensures the DLL directory is inherited by the
    child process.
  - **Unix**: Set `LD_LIBRARY_PATH` (Linux) or `DYLD_LIBRARY_PATH` (macOS) in
    the environment, which works correctly with Erlang ports.

  ## Usage

      {:ok, port, os_pid} = NativeLauncher.spawn_executable(exe_path, args, [
        bin_dir: "/path/to/bin",
        cd: "/path/to/bin",
        env: [{"SOME_VAR", "value"}]
      ])

  """

  @doc """
  Spawn a native executable with proper DLL/library path setup.

  Returns `{:ok, port, os_pid}` on success or `{:error, reason}` on failure.

  ## Options

  - `:bin_dir` - Directory containing DLLs/shared libraries (required on Windows)
  - `:cd` - Working directory for the spawned process
  - `:env` - Additional environment variables as `[{key, value}]` list
  - `:port_opts` - Additional options to pass to `Port.open`

  ## Examples

      {:ok, port, os_pid} = NativeLauncher.spawn_executable(
        "/path/to/llama-server.exe",
        ["--model", model_path, "--port", "8080"],
        bin_dir: LeaxerCore.BinaryFinder.priv_bin_dir()
      )
  """
  @spec spawn_executable(String.t(), [String.t()], keyword()) ::
          {:ok, port(), non_neg_integer() | nil} | {:error, term()}
  def spawn_executable(exe_path, args, opts \\ []) do
    case :os.type() do
      {:win32, _} ->
        LeaxerCore.NativeLauncher.Windows.spawn_executable(exe_path, args, opts)

      _ ->
        LeaxerCore.NativeLauncher.Unix.spawn_executable(exe_path, args, opts)
    end
  end

  @doc """
  Build environment variables for a child process.

  On Windows, prepends the bin_dir to PATH.
  On Unix, prepends bin_dir to LD_LIBRARY_PATH or DYLD_LIBRARY_PATH.

  Returns environment as charlist tuples suitable for `Port.open` `:env` option.
  """
  @spec build_process_env(String.t(), [{String.t(), String.t()}]) :: [{charlist(), charlist()}]
  def build_process_env(bin_dir, additional_env \\ []) do
    case :os.type() do
      {:win32, _} ->
        LeaxerCore.NativeLauncher.Windows.build_process_env(bin_dir, additional_env)

      _ ->
        LeaxerCore.NativeLauncher.Unix.build_process_env(bin_dir, additional_env)
    end
  end
end
