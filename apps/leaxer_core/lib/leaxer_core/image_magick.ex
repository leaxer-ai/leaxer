defmodule LeaxerCore.ImageMagick do
  @moduledoc """
  Wrapper for ImageMagick command-line operations.
  Provides a centralized interface for image processing tasks.

  Supports both bundled binary (in priv/bin/) and system-installed ImageMagick.
  """

  alias LeaxerCore.BinaryFinder

  require Logger

  @doc """
  Get the path to the ImageMagick binary.
  Checks bundled binary first, then falls back to system PATH.
  """
  def bin_path do
    BinaryFinder.find_binary("magick", system_fallback: true)
  end

  @doc """
  Get the path to the bundled ImageMagick binary.
  """
  def bundled_bin_path do
    BinaryFinder.priv_bin_path("magick")
  end

  @doc """
  Check if ImageMagick is installed and available.
  Returns {:ok, version} if available, {:error, reason} otherwise.
  """
  def check_installation do
    case bin_path() do
      nil ->
        {:error, "ImageMagick not found. Install it or place 'magick' binary in priv/bin/"}

      path ->
        case System.cmd(path, ["-version"], stderr_to_stdout: true) do
          {output, 0} ->
            version =
              output
              |> String.split("\n")
              |> List.first()
              |> String.trim()

            {:ok, version}

          {_output, _code} ->
            {:error, "ImageMagick binary found but failed to run"}
        end
    end
  rescue
    e ->
      {:error, "Failed to check ImageMagick: #{Exception.message(e)}"}
  end

  @doc """
  Create a new image from scratch (no input file required).

  Used for generating solid colors, gradients, and other canvas operations.

  ## Examples

      iex> create(output, ["-size", "100x100", "xc:white"])
      {:ok, output_path}

      iex> create(output, ["-size", "100x100", "radial-gradient:white-black"])
      {:ok, output_path}
  """
  def create(output_path, args) when is_list(args) do
    case bin_path() do
      nil ->
        {:error, "ImageMagick not available"}

      magick ->
        # Build command: magick [operations] output
        full_args = args ++ [output_path]

        case System.cmd(magick, full_args, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, output_path}

          {error, code} ->
            Logger.error("ImageMagick create failed (exit #{code}): #{error}")
            {:error, "ImageMagick operation failed: #{error}"}
        end
    end
  rescue
    e ->
      Logger.error("ImageMagick exception: #{inspect(e)}")
      {:error, "ImageMagick error: #{Exception.message(e)}"}
  end

  @doc """
  Execute a convert operation with the given arguments.

  ## Examples

      iex> convert(input, output, ["-resize", "800x600"])
      {:ok, output_path}
  """
  def convert(input_path, output_path, args) when is_list(args) do
    case bin_path() do
      nil ->
        {:error, "ImageMagick not available"}

      magick ->
        if !File.exists?(input_path) do
          {:error, "Input file not found: #{input_path}"}
        else
          # Build full command: magick input [operations] output
          full_args = [input_path] ++ args ++ [output_path]

          case System.cmd(magick, full_args, stderr_to_stdout: true) do
            {_output, 0} ->
              {:ok, output_path}

            {error, code} ->
              Logger.error("ImageMagick convert failed (exit #{code}): #{error}")
              {:error, "ImageMagick operation failed: #{error}"}
          end
        end
    end
  rescue
    e ->
      Logger.error("ImageMagick exception: #{inspect(e)}")
      {:error, "ImageMagick error: #{Exception.message(e)}"}
  end

  @doc """
  Get image information using identify command.

  Returns {:ok, %{width: int, height: int, format: string, size_bytes: int}}
  """
  def identify(image_path) do
    case bin_path() do
      nil ->
        {:error, "ImageMagick not available"}

      magick ->
        if !File.exists?(image_path) do
          {:error, "File not found: #{image_path}"}
        else
          # Format: width height format filesize
          format_string = "%w %h %m %b"

          case System.cmd(magick, ["identify", "-format", format_string, image_path],
                 stderr_to_stdout: true
               ) do
            {output, 0} ->
              case String.split(String.trim(output), " ") do
                [width, height, format, size] ->
                  {:ok,
                   %{
                     width: String.to_integer(width),
                     height: String.to_integer(height),
                     format: format,
                     size_bytes: parse_size(size)
                   }}

                _ ->
                  {:error, "Failed to parse identify output: #{output}"}
              end

            {error, _code} ->
              {:error, "Identify failed: #{error}"}
          end
        end
    end
  rescue
    e ->
      {:error, "Identify error: #{Exception.message(e)}"}
  end

  @doc """
  Create a montage (grid) from multiple images.

  ## Options
  - :columns - number of columns (default: 3)
  - :rows - number of rows (default: 3)
  - :geometry - tile geometry like "200x200+10+10" (size+spacing)
  - :background - background color (default: "white")
  """
  def montage(input_paths, output_path, opts \\ []) do
    case bin_path() do
      nil ->
        {:error, "ImageMagick not available"}

      magick ->
        columns = Keyword.get(opts, :columns, 3)
        rows = Keyword.get(opts, :rows, 3)
        geometry = Keyword.get(opts, :geometry, "200x200+10+10")
        background = Keyword.get(opts, :background, "white")

        args =
          [
            "montage"
          ] ++
            input_paths ++
            [
              "-tile",
              "#{columns}x#{rows}",
              "-geometry",
              geometry,
              "-background",
              background,
              output_path
            ]

        case System.cmd(magick, args, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, output_path}

          {error, _code} ->
            {:error, "Montage failed: #{error}"}
        end
    end
  rescue
    e ->
      {:error, "Montage error: #{Exception.message(e)}"}
  end

  @doc """
  Composite two images together.

  ## Options
  - :mode - blend mode (default: "over")
  - :gravity - position gravity (default: "center")
  - :geometry - offset geometry
  """
  def composite(base_path, overlay_path, output_path, opts \\ []) do
    case bin_path() do
      nil ->
        {:error, "ImageMagick not available"}

      magick ->
        mode = Keyword.get(opts, :mode, "over")
        gravity = Keyword.get(opts, :gravity, "center")

        args = [
          "composite",
          "-compose",
          mode,
          "-gravity",
          gravity,
          overlay_path,
          base_path,
          output_path
        ]

        case System.cmd(magick, args, stderr_to_stdout: true) do
          {_output, 0} ->
            {:ok, output_path}

          {error, _code} ->
            {:error, "Composite failed: #{error}"}
        end
    end
  rescue
    e ->
      {:error, "Composite error: #{Exception.message(e)}"}
  end

  # Private helpers

  defp parse_size(size_str) do
    # Handle sizes like "1234B", "1.2KB", "3.4MB"
    case Regex.run(~r/([\d.]+)(\w+)/, size_str) do
      [_, num, unit] ->
        base = String.to_float(num)

        multiplier =
          case String.upcase(unit) do
            "B" -> 1
            "KB" -> 1024
            "MB" -> 1024 * 1024
            "GB" -> 1024 * 1024 * 1024
            _ -> 1
          end

        round(base * multiplier)

      _ ->
        0
    end
  rescue
    # ArgumentError can occur from String.to_float with invalid input
    ArgumentError -> 0
  end
end
