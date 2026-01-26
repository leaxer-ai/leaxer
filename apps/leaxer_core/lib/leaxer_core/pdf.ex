defmodule LeaxerCore.Pdf do
  @moduledoc """
  PDF text extraction using pdftotext from Poppler.

  Looks for bundled pdftotext in priv/bin/ first, then falls back to system PATH.
  """

  require Logger

  alias LeaxerCore.BinaryFinder

  @doc """
  Extracts text content from a PDF file.

  Returns `{:ok, text}` on success or `{:error, reason}` on failure.
  """
  @spec extract_text(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_text(pdf_path) do
    # Verify file exists
    unless File.exists?(pdf_path) do
      {:error, "File not found: #{pdf_path}"}
    else
      case find_pdftotext() do
        {:ok, pdftotext_path} ->
          run_pdftotext(pdftotext_path, pdf_path)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Extracts text from PDF binary data.

  Creates a temporary file, extracts text, and cleans up.
  """
  @spec extract_text_from_binary(binary()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_text_from_binary(pdf_data) when is_binary(pdf_data) do
    # Create temp file
    tmp_dir = System.tmp_dir!()
    timestamp = System.os_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    tmp_path = Path.join(tmp_dir, "leaxer_pdf_#{timestamp}_#{random}.pdf")

    try do
      case File.write(tmp_path, pdf_data) do
        :ok ->
          extract_text(tmp_path)

        {:error, reason} ->
          {:error, "Failed to write temp file: #{inspect(reason)}"}
      end
    after
      # Clean up temp file
      File.rm(tmp_path)
    end
  end

  @doc """
  Checks if pdftotext is available (bundled or system).
  """
  @spec available?() :: boolean()
  def available? do
    case find_pdftotext() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Find pdftotext binary - bundled first, then system PATH
  defp find_pdftotext do
    # First check bundled binary in priv/bin/
    case BinaryFinder.find_binary("pdftotext", system_fallback: true) do
      nil ->
        {:error, "pdftotext not found. Please install Poppler."}

      path ->
        {:ok, path}
    end
  end

  # Run pdftotext command
  defp run_pdftotext(pdftotext_path, pdf_path) do
    # Use "-" as output to write to stdout
    # -layout preserves layout, -enc UTF-8 ensures UTF-8 output
    # Use absolute path for the PDF since we change working directory
    abs_pdf_path = Path.expand(pdf_path)
    args = ["-layout", "-enc", "UTF-8", abs_pdf_path, "-"]

    Logger.debug("Running pdftotext: #{pdftotext_path} #{Enum.join(args, " ")}")

    # Run from the binary's directory so DLLs are found on Windows
    bin_dir = Path.dirname(pdftotext_path)

    case System.cmd(pdftotext_path, args, stderr_to_stdout: true, cd: bin_dir) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {error_output, exit_code} ->
        Logger.error("pdftotext failed with exit code #{exit_code}: #{error_output}")
        {:error, "pdftotext failed: #{String.trim(error_output)}"}
    end
  end
end
