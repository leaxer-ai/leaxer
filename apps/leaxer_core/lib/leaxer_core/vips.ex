defmodule LeaxerCore.Vips do
  @moduledoc """
  Wrapper for libvips command-line operations.

  Provides a centralized interface for image processing tasks using the bundled
  vips binary. All operations work with both base64 and path-based inputs,
  returning base64 output by default to keep images in memory.

  ## Architecture

  - Input: Accepts both `%{data: base64, mime_type: ...}` and `%{path: "..."}` formats
  - Processing: Materializes to temp file only when calling vips CLI
  - Output: Returns `%{data: base64, mime_type: "image/png"}` (in-memory)
  - Cleanup: Temp files are deleted after operation

  ## Performance

  vips is 4-5x faster than ImageMagick for most operations and uses streaming
  I/O which reduces memory usage for large images.
  """

  require Logger

  @type image :: %{data: String.t(), mime_type: String.t()} | %{path: String.t()}
  @type result :: {:ok, %{data: String.t(), mime_type: String.t()}} | {:error, String.t()}
  @type dimensions :: %{width: integer(), height: integer()}

  # Get vips executable path
  defp vips_bin do
    tools_dir = Application.get_env(:leaxer_core, :tools_dir, "tools")
    Path.join([tools_dir, "vips-dev-8.18", "bin", "vips.exe"])
  end

  defp vipsheader_bin do
    tools_dir = Application.get_env(:leaxer_core, :tools_dir, "tools")
    Path.join([tools_dir, "vips-dev-8.18", "bin", "vipsheader.exe"])
  end

  @doc """
  Check if vips is available.
  """
  @spec available?() :: boolean()
  def available? do
    File.exists?(vips_bin())
  end

  # ===========================================================================
  # Core Operations
  # ===========================================================================

  @doc """
  Get image dimensions and metadata.

  Returns `{:ok, %{width: w, height: h, format: fmt, bands: n}}` or `{:error, reason}`.
  """
  @spec identify(image()) :: {:ok, map()} | {:error, String.t()}
  def identify(image) do
    with_materialized_input(image, fn input_path ->
      vipsheader = vipsheader_bin()

      if not File.exists?(vipsheader) do
        {:error, "vipsheader not found"}
      else
        with {:ok, width} <- get_header(vipsheader, input_path, "width"),
             {:ok, height} <- get_header(vipsheader, input_path, "height"),
             {:ok, bands} <- get_header(vipsheader, input_path, "bands") do
          # Get file size
          size_bytes =
            case File.stat(input_path) do
              {:ok, %{size: size}} -> size
              _ -> 0
            end

          # Detect format from extension
          format = input_path |> Path.extname() |> String.trim_leading(".") |> String.upcase()

          {:ok,
           %{
             width: String.to_integer(width),
             height: String.to_integer(height),
             bands: String.to_integer(bands),
             format: format,
             size_bytes: size_bytes
           }}
        end
      end
    end)
  end

  defp get_header(vipsheader, path, field) do
    case System.cmd(vipsheader, ["-f", field, path], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, "Failed to get #{field}: #{error}"}
    end
  end

  @doc """
  Resize image to target dimensions.

  ## Options

  - `:kernel` - Resampling kernel: "nearest", "linear", "cubic", "lanczos2", "lanczos3" (default)
  - `:maintain_aspect` - If true, resize to fit within dimensions (default: true)
  """
  @spec resize(image(), integer(), integer(), keyword()) :: result()
  def resize(image, width, height, opts \\ []) do
    kernel = Keyword.get(opts, :kernel, "lanczos3")
    maintain_aspect = Keyword.get(opts, :maintain_aspect, true)

    with_temp_io(image, fn input_path, output_path ->
      # Get current dimensions
      case identify(%{path: input_path}) do
        {:ok, %{width: curr_w, height: curr_h}} ->
          if maintain_aspect do
            # Calculate scale to fit within target dimensions
            scale = min(width / curr_w, height / curr_h)
            run_vips(["resize", input_path, output_path, "#{scale}", "--kernel", kernel])
          else
            # Independent scaling for each axis
            scale_x = width / curr_w
            scale_y = height / curr_h

            run_vips([
              "resize",
              input_path,
              output_path,
              "#{scale_x}",
              "--vscale",
              "#{scale_y}",
              "--kernel",
              kernel
            ])
          end

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Crop image to specified region.

  For center crop, use `crop_center/3`.
  """
  @spec crop(image(), integer(), integer(), integer(), integer()) :: result()
  def crop(image, x, y, width, height) do
    with_temp_io(image, fn input_path, output_path ->
      run_vips(["crop", input_path, output_path, "#{x}", "#{y}", "#{width}", "#{height}"])
    end)
  end

  @doc """
  Center crop image to specified dimensions.
  """
  @spec crop_center(image(), integer(), integer()) :: result()
  def crop_center(image, width, height) do
    with_temp_io(image, fn input_path, output_path ->
      case identify(%{path: input_path}) do
        {:ok, %{width: curr_w, height: curr_h}} ->
          x = max(0, div(curr_w - width, 2))
          y = max(0, div(curr_h - height, 2))
          # Clamp dimensions to available space
          actual_w = min(width, curr_w - x)
          actual_h = min(height, curr_h - y)

          run_vips([
            "crop",
            input_path,
            output_path,
            "#{x}",
            "#{y}",
            "#{actual_w}",
            "#{actual_h}"
          ])

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Rotate image by 90, 180, or 270 degrees.
  """
  @spec rotate(image(), integer()) :: result()
  def rotate(image, angle) when angle in [90, 180, 270] do
    direction =
      case angle do
        90 -> "d90"
        180 -> "d180"
        270 -> "d270"
      end

    with_temp_io(image, fn input_path, output_path ->
      run_vips(["rot", input_path, output_path, direction])
    end)
  end

  @doc """
  Rotate image by arbitrary angle.

  ## Options

  - `:background` - Background color for exposed areas (default: "0 0 0")
  """
  @spec rotate_arbitrary(image(), number(), keyword()) :: result()
  def rotate_arbitrary(image, angle, opts \\ []) do
    background = Keyword.get(opts, :background, "0 0 0")

    with_temp_io(image, fn input_path, output_path ->
      run_vips([
        "similarity",
        input_path,
        output_path,
        "--angle",
        "#{angle}",
        "--background",
        background
      ])
    end)
  end

  @doc """
  Flip image horizontally or vertically.

  Direction can be `:horizontal` or `:vertical`.
  """
  @spec flip(image(), :horizontal | :vertical) :: result()
  def flip(image, direction) do
    vips_direction =
      case direction do
        :horizontal -> "horizontal"
        :vertical -> "vertical"
      end

    with_temp_io(image, fn input_path, output_path ->
      run_vips(["flip", input_path, output_path, vips_direction])
    end)
  end

  @doc """
  Apply Gaussian blur to image.
  """
  @spec blur(image(), number()) :: result()
  def blur(image, sigma) when sigma > 0 do
    with_temp_io(image, fn input_path, output_path ->
      run_vips(["gaussblur", input_path, output_path, "#{sigma}"])
    end)
  end

  @doc """
  Sharpen image using unsharp mask.

  ## Options

  - `:sigma` - Gaussian blur sigma (default: 1.0)
  - `:x1` - Flat/jagged threshold (default: 2.0)
  - `:y2` - Maximum brightening (default: 10.0)
  - `:y3` - Maximum darkening (default: 20.0)
  - `:m1` - Slope for flat areas (default: 0.0)
  - `:m2` - Slope for jagged areas (default: 3.0)
  """
  @spec sharpen(image(), keyword()) :: result()
  def sharpen(image, opts \\ []) do
    sigma = Keyword.get(opts, :sigma, 1.0)

    with_temp_io(image, fn input_path, output_path ->
      run_vips(["sharpen", input_path, output_path, "--sigma", "#{sigma}"])
    end)
  end

  @doc """
  Adjust brightness and contrast using linear transform.

  - `brightness`: Added to each pixel (-255 to 255, 0 = no change)
  - `contrast`: Multiplied with each pixel (0.0 to 3.0, 1.0 = no change)
  """
  @spec adjust_brightness_contrast(image(), number(), number()) :: result()
  def adjust_brightness_contrast(image, brightness, contrast) do
    with_temp_io(image, fn input_path, output_path ->
      # vips linear: output = input * a + b
      # For RGB images, we need to apply to all bands
      run_vips(["linear", input_path, output_path, "#{contrast}", "#{brightness}"])
    end)
  end

  @doc """
  Adjust saturation.

  - `saturation`: Multiplier (0.0 = grayscale, 1.0 = no change, 2.0 = double saturation)
  """
  @spec adjust_saturation(image(), number()) :: result()
  def adjust_saturation(image, saturation) when saturation >= 0 do
    with_temp_io(image, fn input_path, output_path ->
      temp_dir = LeaxerCore.Paths.tmp_dir()
      uid = :erlang.unique_integer([:positive])

      # Convert to LCH (Lightness, Chroma, Hue) color space
      lch_path = Path.join(temp_dir, "lch_#{uid}.v")

      with :ok <- run_vips(["colourspace", input_path, lch_path, "lch"]),
           # Extract and modify chroma (saturation) channel
           :ok <-
             run_vips(["linear", lch_path, output_path <> ".lch", "1 #{saturation} 1", "0 0 0"]),
           # Convert back to sRGB
           :ok <- run_vips(["colourspace", output_path <> ".lch", output_path, "srgb"]) do
        File.rm(lch_path)
        File.rm(output_path <> ".lch")
        :ok
      end
    end)
  end

  @doc """
  Add a solid color border around image.

  ## Options

  - `:color` - Border color as hex string (default: "#000000")
  """
  @spec add_border(image(), integer(), keyword()) :: result()
  def add_border(image, border_width, opts \\ []) do
    color = Keyword.get(opts, :color, "#000000")

    # Parse hex color to RGB values
    {r, g, b} = parse_hex_color(color)

    with_temp_io(image, fn input_path, output_path ->
      case identify(%{path: input_path}) do
        {:ok, %{width: w, height: h}} ->
          new_w = w + border_width * 2
          new_h = h + border_width * 2

          # vips embed places image at (x, y) in a canvas of (new_w x new_h)
          # --extend specifies what to fill the new areas with
          run_vips([
            "embed",
            input_path,
            output_path,
            "#{border_width}",
            "#{border_width}",
            "#{new_w}",
            "#{new_h}",
            "--extend",
            "background",
            "--background",
            "#{r} #{g} #{b}"
          ])

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Composite two images together.

  ## Modes

  - `:over` - Standard alpha compositing (default)
  - `:multiply` - Multiply blend
  - `:screen` - Screen blend
  - `:overlay` - Overlay blend
  - `:add` - Additive blend

  ## Options

  - `:mode` - Blend mode (default: :over)
  - `:x` - X offset for overlay (default: 0)
  - `:y` - Y offset for overlay (default: 0)
  """
  @spec composite(image(), image(), keyword()) :: result()
  def composite(base, overlay, opts \\ []) do
    mode = Keyword.get(opts, :mode, :over)
    x = Keyword.get(opts, :x, 0)
    y = Keyword.get(opts, :y, 0)

    vips_mode =
      case mode do
        :over -> "over"
        :multiply -> "multiply"
        :screen -> "screen"
        :overlay -> "overlay"
        :add -> "add"
        other -> to_string(other)
      end

    with {:ok, base_path} <- materialize_to_temp(base),
         {:ok, overlay_path} <- materialize_to_temp(overlay) do
      temp_dir = LeaxerCore.Paths.tmp_dir()
      uid = :erlang.unique_integer([:positive])
      output_path = Path.join(temp_dir, "composite_#{uid}.png")

      result =
        if x == 0 and y == 0 do
          # Simple composite at origin
          run_vips(["composite2", overlay_path, base_path, output_path, vips_mode])
        else
          # Need to embed overlay at offset first
          case identify(%{path: base_path}) do
            {:ok, %{width: base_w, height: base_h}} ->
              embedded_path = Path.join(temp_dir, "embedded_#{uid}.png")

              with :ok <-
                     run_vips([
                       "embed",
                       overlay_path,
                       embedded_path,
                       "#{x}",
                       "#{y}",
                       "#{base_w}",
                       "#{base_h}",
                       "--extend",
                       "black"
                     ]),
                   :ok <-
                     run_vips(["composite2", embedded_path, base_path, output_path, vips_mode]) do
                File.rm(embedded_path)
                :ok
              end

            {:error, reason} ->
              {:error, reason}
          end
        end

      case result do
        :ok ->
          result = read_as_base64(output_path)
          cleanup_temp_files([base_path, overlay_path, output_path])
          result

        {:error, reason} ->
          cleanup_temp_files([base_path, overlay_path, output_path])
          {:error, reason}
      end
    end
  end

  @doc """
  Create a montage (grid) from multiple images.

  ## Options

  - `:columns` - Number of columns (default: auto-calculated)
  - `:background` - Background color (default: "0 0 0")
  - `:shim` - Gap between images in pixels (default: 0)
  """
  @spec montage([image()], keyword()) :: result()
  def montage(images, opts \\ []) when is_list(images) and length(images) > 0 do
    columns = Keyword.get(opts, :columns, ceil(:math.sqrt(length(images))))
    shim = Keyword.get(opts, :shim, 0)

    # Materialize all images
    materialized =
      Enum.map(images, fn img ->
        case materialize_to_temp(img) do
          {:ok, path} -> {:ok, path}
          error -> error
        end
      end)

    errors = Enum.filter(materialized, &match?({:error, _}, &1))

    if length(errors) > 0 do
      # Cleanup any successfully materialized files
      materialized
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.each(fn {:ok, path} -> File.rm(path) end)

      {:error, "Failed to materialize some images"}
    else
      paths = Enum.map(materialized, fn {:ok, path} -> path end)
      temp_dir = LeaxerCore.Paths.tmp_dir()
      uid = :erlang.unique_integer([:positive])
      output_path = Path.join(temp_dir, "montage_#{uid}.png")

      # Build arrayjoin command
      # vips arrayjoin "img1 img2 img3..." output --across=columns
      images_arg = Enum.join(paths, " ")

      args =
        ["arrayjoin", images_arg, output_path, "--across", "#{columns}"] ++
          if shim > 0, do: ["--shim", "#{shim}"], else: []

      result = run_vips(args)

      case result do
        :ok ->
          result = read_as_base64(output_path)
          cleanup_temp_files(paths ++ [output_path])
          result

        {:error, reason} ->
          cleanup_temp_files(paths ++ [output_path])
          {:error, reason}
      end
    end
  end

  @doc """
  Create text image for watermarking.

  ## Options

  - `:font` - Font specification (default: "sans 24")
  - `:dpi` - Resolution (default: 72)
  - `:rgba` - If true, create RGBA image (default: true)
  """
  @spec text(String.t(), keyword()) :: result()
  def text(text_content, opts \\ []) do
    font = Keyword.get(opts, :font, "sans 24")
    dpi = Keyword.get(opts, :dpi, 72)
    rgba = Keyword.get(opts, :rgba, true)

    temp_dir = LeaxerCore.Paths.tmp_dir()
    File.mkdir_p!(temp_dir)
    uid = :erlang.unique_integer([:positive])
    output_path = Path.join(temp_dir, "text_#{uid}.png")

    args =
      ["text", output_path, text_content, "--font", font, "--dpi", "#{dpi}"] ++
        if rgba, do: ["--rgba"], else: []

    case run_vips(args) do
      :ok ->
        result = read_as_base64(output_path)
        File.rm(output_path)
        result

      {:error, reason} ->
        File.rm(output_path)
        {:error, reason}
    end
  end

  @doc """
  Smart crop - automatically finds interesting region to crop.

  Uses vips smartcrop with "attention" mode by default.
  """
  @spec smartcrop(image(), integer(), integer(), keyword()) :: result()
  def smartcrop(image, width, height, opts \\ []) do
    interesting = Keyword.get(opts, :interesting, "attention")

    with_temp_io(image, fn input_path, output_path ->
      run_vips([
        "smartcrop",
        input_path,
        output_path,
        "#{width}",
        "#{height}",
        "--interesting",
        interesting
      ])
    end)
  end

  @doc """
  Thumbnail - fast resize with smart cropping.

  Useful for creating thumbnails that preserve the interesting part of images.
  """
  @spec thumbnail(image(), integer(), keyword()) :: result()
  def thumbnail(image, size, opts \\ []) do
    height = Keyword.get(opts, :height, size)
    crop = Keyword.get(opts, :crop, "centre")

    with_temp_io(image, fn input_path, output_path ->
      run_vips([
        "thumbnail",
        input_path,
        output_path,
        "#{size}",
        "--height",
        "#{height}",
        "--crop",
        crop
      ])
    end)
  end

  # ===========================================================================
  # Mask Operations (for MaskToSEGS)
  # ===========================================================================

  @doc """
  Threshold image to binary (black/white).

  Pixels >= threshold become white (255), others become black (0).
  """
  @spec threshold(image(), integer()) :: result()
  def threshold(image, threshold_value) do
    with_temp_io(image, fn input_path, output_path ->
      temp_dir = LeaxerCore.Paths.tmp_dir()
      uid = :erlang.unique_integer([:positive])

      # First convert to single band if needed
      gray_path = Path.join(temp_dir, "gray_#{uid}.png")

      with :ok <- run_vips(["colourspace", input_path, gray_path, "b-w"]),
           # Apply threshold: relational_const moreeq returns 255 where condition is true
           :ok <-
             run_vips([
               "relational_const",
               gray_path,
               output_path,
               "moreeq",
               "#{threshold_value}"
             ]) do
        File.rm(gray_path)
        :ok
      end
    end)
  end

  @doc """
  Label connected regions in a binary mask image.

  Returns labeled image where each connected region has a unique integer value.
  """
  @spec label_regions(image()) :: result()
  def label_regions(image) do
    with_temp_io(image, fn input_path, output_path ->
      run_vips(["labelregions", input_path, output_path])
    end)
  end

  @doc """
  Create a solid color canvas.
  """
  @spec create_canvas(integer(), integer(), keyword()) :: result()
  def create_canvas(width, height, opts \\ []) do
    color = Keyword.get(opts, :color, "0 0 0")

    temp_dir = LeaxerCore.Paths.tmp_dir()
    File.mkdir_p!(temp_dir)
    uid = :erlang.unique_integer([:positive])
    output_path = Path.join(temp_dir, "canvas_#{uid}.png")

    # Create black canvas first, then fill with color if needed
    case run_vips(["black", output_path, "#{width}", "#{height}"]) do
      :ok ->
        if color != "0 0 0" and color != "0" do
          # Fill with color using linear transform
          filled_path = Path.join(temp_dir, "filled_#{uid}.png")

          case run_vips(["linear", output_path, filled_path, "1", color]) do
            :ok ->
              File.rm(output_path)
              result = read_as_base64(filled_path)
              File.rm(filled_path)
              result

            {:error, reason} ->
              File.rm(output_path)
              {:error, reason}
          end
        else
          result = read_as_base64(output_path)
          File.rm(output_path)
          result
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Insert one image into another at specified position.
  """
  @spec insert(image(), image(), integer(), integer()) :: result()
  def insert(base, overlay, x, y) do
    with {:ok, base_path} <- materialize_to_temp(base),
         {:ok, overlay_path} <- materialize_to_temp(overlay) do
      temp_dir = LeaxerCore.Paths.tmp_dir()
      uid = :erlang.unique_integer([:positive])
      output_path = Path.join(temp_dir, "insert_#{uid}.png")

      result = run_vips(["insert", base_path, overlay_path, output_path, "#{x}", "#{y}"])

      case result do
        :ok ->
          result = read_as_base64(output_path)
          cleanup_temp_files([base_path, overlay_path, output_path])
          result

        {:error, reason} ->
          cleanup_temp_files([base_path, overlay_path, output_path])
          {:error, reason}
      end
    end
  end

  @doc """
  Blend using mask (ifthenelse with blend flag).

  Where mask is white, use `then_image`; where black, use `else_image`.
  Gray values blend smoothly between the two.
  """
  @spec ifthenelse(image(), image(), image()) :: result()
  def ifthenelse(mask, then_image, else_image) do
    with {:ok, mask_path} <- materialize_to_temp(mask),
         {:ok, then_path} <- materialize_to_temp(then_image),
         {:ok, else_path} <- materialize_to_temp(else_image) do
      temp_dir = LeaxerCore.Paths.tmp_dir()
      uid = :erlang.unique_integer([:positive])
      output_path = Path.join(temp_dir, "blend_#{uid}.png")

      result = run_vips(["ifthenelse", mask_path, then_path, else_path, output_path, "--blend"])

      case result do
        :ok ->
          result = read_as_base64(output_path)
          cleanup_temp_files([mask_path, then_path, else_path, output_path])
          result

        {:error, reason} ->
          cleanup_temp_files([mask_path, then_path, else_path, output_path])
          {:error, reason}
      end
    end
  end

  # ===========================================================================
  # Path-based operations (for external tools that need file paths)
  # ===========================================================================

  @doc """
  Materialize an image to a temp file path.

  Use this when you need to pass an image to an external tool that requires a file path.
  Remember to clean up the file when done.
  """
  @spec materialize_to_temp(image()) :: {:ok, String.t()} | {:error, String.t()}
  def materialize_to_temp(image) do
    case image do
      %{path: path} when is_binary(path) ->
        if File.exists?(path) do
          {:ok, path}
        else
          {:error, "Image file not found: #{path}"}
        end

      %{"path" => path} when is_binary(path) ->
        if File.exists?(path) do
          {:ok, path}
        else
          {:error, "Image file not found: #{path}"}
        end

      %{data: data, mime_type: _mime_type} when is_binary(data) ->
        write_base64_to_temp(data)

      %{"data" => data, "mime_type" => _mime_type} when is_binary(data) ->
        write_base64_to_temp(data)

      _ ->
        {:error, "Invalid image format"}
    end
  end

  @doc """
  Write result to a file path instead of returning base64.

  Use this when you need to save to the outputs directory.
  """
  @spec write_to_path(image(), String.t()) :: :ok | {:error, String.t()}
  def write_to_path(image, output_path) do
    case image do
      %{data: data} when is_binary(data) ->
        case Base.decode64(data) do
          {:ok, binary} ->
            File.mkdir_p!(Path.dirname(output_path))
            File.write!(output_path, binary)
            :ok

          :error ->
            {:error, "Invalid base64 data"}
        end

      %{"data" => data} when is_binary(data) ->
        case Base.decode64(data) do
          {:ok, binary} ->
            File.mkdir_p!(Path.dirname(output_path))
            File.write!(output_path, binary)
            :ok

          :error ->
            {:error, "Invalid base64 data"}
        end

      %{path: path} when is_binary(path) ->
        if File.exists?(path) do
          File.mkdir_p!(Path.dirname(output_path))
          File.cp!(path, output_path)
          :ok
        else
          {:error, "Source file not found: #{path}"}
        end

      %{"path" => path} when is_binary(path) ->
        if File.exists?(path) do
          File.mkdir_p!(Path.dirname(output_path))
          File.cp!(path, output_path)
          :ok
        else
          {:error, "Source file not found: #{path}"}
        end

      _ ->
        {:error, "Invalid image format"}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Run a vips command and return :ok or {:error, reason}
  defp run_vips(args) when is_list(args) do
    vips = vips_bin()

    if not File.exists?(vips) do
      {:error, "vips not found at #{vips}"}
    else
      Logger.debug("[Vips] Running: vips #{Enum.join(args, " ")}")

      case System.cmd(vips, args, stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        {error, code} ->
          Logger.error("[Vips] Command failed (exit #{code}): #{error}")
          {:error, "vips operation failed: #{String.trim(error)}"}
      end
    end
  end

  # Execute operation with automatic temp file management
  defp with_temp_io(image, operation) do
    case materialize_to_temp(image) do
      {:ok, input_path} ->
        temp_dir = LeaxerCore.Paths.tmp_dir()
        File.mkdir_p!(temp_dir)
        uid = :erlang.unique_integer([:positive])
        output_path = Path.join(temp_dir, "vips_out_#{uid}.png")

        result = operation.(input_path, output_path)

        case result do
          :ok ->
            base64_result = read_as_base64(output_path)
            # Clean up temp files (but not if input was already a path)
            unless image_is_path?(image), do: File.rm(input_path)
            File.rm(output_path)
            base64_result

          {:error, reason} ->
            unless image_is_path?(image), do: File.rm(input_path)
            File.rm(output_path)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Execute operation with materialized input (doesn't create output file)
  defp with_materialized_input(image, operation) do
    case materialize_to_temp(image) do
      {:ok, input_path} ->
        result = operation.(input_path)
        unless image_is_path?(image), do: File.rm(input_path)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp image_is_path?(%{path: _}), do: true
  defp image_is_path?(%{"path" => _}), do: true
  defp image_is_path?(_), do: false

  defp write_base64_to_temp(base64_data) do
    case Base.decode64(base64_data) do
      {:ok, binary} ->
        temp_dir = LeaxerCore.Paths.tmp_dir()
        File.mkdir_p!(temp_dir)
        uid = :erlang.unique_integer([:positive])
        timestamp = System.system_time(:millisecond)
        path = Path.join(temp_dir, "vips_in_#{timestamp}_#{uid}.png")

        case File.write(path, binary) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, "Failed to write temp file: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Invalid base64 data"}
    end
  end

  defp read_as_base64(path) do
    case File.read(path) do
      {:ok, binary} ->
        {:ok, %{data: Base.encode64(binary), mime_type: "image/png"}}

      {:error, reason} ->
        {:error, "Failed to read output: #{inspect(reason)}"}
    end
  end

  defp cleanup_temp_files(paths) do
    Enum.each(paths, fn path ->
      if path && File.exists?(path) do
        File.rm(path)
      end
    end)
  end

  defp parse_hex_color(hex) do
    hex = String.trim_leading(hex, "#")

    case hex do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> ->
        {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}

      _ ->
        {0, 0, 0}
    end
  end
end
