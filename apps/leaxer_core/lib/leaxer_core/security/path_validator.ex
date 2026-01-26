defmodule LeaxerCore.Security.PathValidator do
  @moduledoc """
  Path validation to prevent traversal attacks.

  This module provides functions to sanitize filenames and validate that paths
  stay within allowed directories, preventing path traversal vulnerabilities
  (e.g., `../../../etc/passwd`).
  """

  @doc """
  Sanitize a filename by extracting only the basename and rejecting dangerous patterns.

  Returns the sanitized filename on success, or an error tuple on failure.

  ## Examples

      iex> PathValidator.sanitize_filename("report.txt")
      "report.txt"

      iex> PathValidator.sanitize_filename("../../../etc/passwd")
      "passwd"

      iex> PathValidator.sanitize_filename("..")
      {:error, :invalid_filename, "Invalid filename"}

      iex> PathValidator.sanitize_filename("")
      {:error, :empty_filename, "Filename cannot be empty"}
  """
  @spec sanitize_filename(String.t()) :: String.t() | {:error, atom(), String.t()}
  def sanitize_filename(filename) when is_binary(filename) do
    sanitized =
      filename
      |> String.trim()
      |> Path.basename()

    cond do
      sanitized == "" ->
        {:error, :empty_filename, "Filename cannot be empty"}

      sanitized in [".", ".."] ->
        {:error, :invalid_filename, "Invalid filename"}

      String.contains?(sanitized, "\0") ->
        {:error, :invalid_filename, "Null bytes not allowed in filename"}

      true ->
        sanitized
    end
  end

  def sanitize_filename(_), do: {:error, :invalid_filename, "Filename must be a string"}

  @doc """
  Validate that a target path stays within the allowed base directory.

  Both paths are expanded to absolute form before comparison to prevent
  path traversal attacks using relative paths or symbolic links.

  Returns `:ok` if the path is valid, or an error tuple if it escapes the base.

  ## Examples

      iex> PathValidator.validate_within_directory("/home/user/downloads/file.txt", "/home/user/downloads")
      :ok

      iex> PathValidator.validate_within_directory("/home/user/downloads/../secrets/key.pem", "/home/user/downloads")
      {:error, :path_traversal, "Path escapes allowed directory"}
  """
  @spec validate_within_directory(String.t(), String.t()) ::
          :ok | {:error, :path_traversal, String.t()}
  def validate_within_directory(target_path, base_directory)
      when is_binary(target_path) and is_binary(base_directory) do
    # Expand both paths to absolute form
    expanded_target = Path.expand(target_path)
    expanded_base = Path.expand(base_directory)

    # Normalize base path to ensure consistent trailing separator handling
    # The target must start with the base path followed by a separator,
    # OR be exactly equal to the base path (for edge cases)
    normalized_base = ensure_trailing_separator(expanded_base)

    if String.starts_with?(expanded_target <> "/", normalized_base) or
         expanded_target == expanded_base do
      :ok
    else
      {:error, :path_traversal, "Path escapes allowed directory"}
    end
  end

  def validate_within_directory(_, _), do: {:error, :path_traversal, "Invalid path arguments"}

  @doc """
  Sanitize a filename and validate the resulting full path stays within the base directory.

  This is a convenience function that combines `sanitize_filename/1` and
  `validate_within_directory/2`.

  Returns `{:ok, full_path}` on success, or an error tuple on failure.

  ## Examples

      iex> PathValidator.sanitize_and_validate("file.txt", "/home/user/downloads")
      {:ok, "/home/user/downloads/file.txt"}

      iex> PathValidator.sanitize_and_validate("../../../etc/passwd", "/home/user/downloads")
      {:ok, "/home/user/downloads/passwd"}
  """
  @spec sanitize_and_validate(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom(), String.t()}
  def sanitize_and_validate(filename, base_directory)
      when is_binary(filename) and is_binary(base_directory) do
    case sanitize_filename(filename) do
      {:error, _, _} = error ->
        error

      sanitized ->
        full_path = Path.join(base_directory, sanitized)

        case validate_within_directory(full_path, base_directory) do
          :ok -> {:ok, full_path}
          error -> error
        end
    end
  end

  def sanitize_and_validate(_, _), do: {:error, :invalid_input, "Invalid arguments"}

  # Ensure the path ends with a trailing separator for consistent comparison
  defp ensure_trailing_separator(path) do
    if String.ends_with?(path, "/") or String.ends_with?(path, "\\") do
      path
    else
      path <> "/"
    end
  end
end
