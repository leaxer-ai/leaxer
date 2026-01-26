defmodule LeaxerCore.Workers.GenerationHelpers do
  @moduledoc """
  Shared helper functions for generation workers (StableDiffusion, StableDiffusionServer).

  Provides common utilities for:
  - ANSI escape code stripping
  - Progress parsing and broadcasting
  - Completion/error broadcasting
  - Output path generation
  """

  require Logger

  # ANSI escape code regex - matches color codes, cursor movements, etc.
  @ansi_regex ~r/\x1b\[[0-9;]*[a-zA-Z]|\[K/

  @doc """
  Strip ANSI escape codes from a string.
  """
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(line) do
    Regex.replace(@ansi_regex, line, "")
  end

  @doc """
  Parse progress from a line using the given regex.

  Returns `{current_step, total_steps}` if matched, `nil` otherwise.
  The regex should have two capture groups: current step and total steps.
  """
  @spec parse_progress(String.t(), Regex.t()) :: {integer(), integer()} | nil
  def parse_progress(line, regex) do
    clean_line = strip_ansi(line)

    case Regex.run(regex, clean_line) do
      [_, current, total] ->
        {String.to_integer(current), String.to_integer(total)}

      _ ->
        nil
    end
  end

  @doc """
  Broadcast progress update to PubSub.

  Phase is determined automatically:
  - "loading" when total_steps > 200 (model loading typically has 1000+ steps)
  - "inference" otherwise (typically 4-150 steps)
  """
  @spec broadcast_progress(String.t() | nil, String.t() | nil, integer(), integer()) :: :ok
  def broadcast_progress(job_id, node_id, current_step, total_steps) do
    phase = if total_steps > 200, do: "loading", else: "inference"
    broadcast_progress(job_id, node_id, current_step, total_steps, phase)
  end

  @doc """
  Broadcast progress update to PubSub with explicit phase.
  """
  @spec broadcast_progress(String.t() | nil, String.t() | nil, integer(), integer(), String.t()) ::
          :ok
  def broadcast_progress(job_id, node_id, current_step, total_steps, phase) do
    percentage = round(current_step / total_steps * 100)

    Phoenix.PubSub.broadcast(LeaxerCore.PubSub, "generation:progress", %{
      job_id: job_id,
      node_id: node_id,
      current_step: current_step,
      total_steps: total_steps,
      percentage: percentage,
      phase: phase
    })
  end

  @doc """
  Broadcast generation completion to PubSub.
  """
  @spec broadcast_completion(String.t() | nil, map()) :: :ok
  def broadcast_completion(job_id, result) do
    Phoenix.PubSub.broadcast(LeaxerCore.PubSub, "generation:complete", %{
      job_id: job_id,
      path: result[:path],
      elapsed_ms: result[:elapsed_ms]
    })
  end

  @doc """
  Broadcast generation error to PubSub.
  """
  @spec broadcast_error(String.t() | nil, String.t()) :: :ok
  def broadcast_error(job_id, error) do
    Phoenix.PubSub.broadcast(LeaxerCore.PubSub, "generation:error", %{
      job_id: job_id,
      error: error
    })
  end

  @doc """
  Generate a unique output path for a generation result.

  Uses tmp_dir by default, or the specified output_dir from opts.
  Extension is determined by mode: "mp4" for video, "png" for images.
  """
  @spec generate_output_path(keyword()) :: String.t()
  def generate_output_path(opts) do
    output_dir = Keyword.get(opts, :output_dir, LeaxerCore.Paths.tmp_dir())
    File.mkdir_p!(output_dir)

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    extension =
      case Keyword.get(opts, :mode) do
        "vid_gen" -> "mp4"
        _ -> "png"
      end

    Path.join(output_dir, "gen_#{timestamp}_#{random}.#{extension}")
  end
end
