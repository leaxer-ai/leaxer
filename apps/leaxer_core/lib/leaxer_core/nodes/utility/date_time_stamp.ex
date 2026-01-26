defmodule LeaxerCore.Nodes.Utility.DateTimeStamp do
  @moduledoc """
  Current date/time in customizable format.

  Essential for organizing output folders by date (2024-01-17_batch1).

  ## Examples

      iex> DateTimeStamp.process(%{}, %{"format" => "iso8601"})
      {:ok, %{"timestamp" => "2024-01-17T10:30:45"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "DateTimeStamp"

  @impl true
  def label, do: "Date/Time Stamp"

  @impl true
  def category, do: "Utility/Format"

  @impl true
  def description, do: "Current date/time in customizable format"

  @impl true
  def input_spec do
    %{
      format: %{
        type: :enum,
        label: "FORMAT",
        default: "iso8601",
        options: [
          %{value: "iso8601", label: "ISO 8601"},
          %{value: "date_only", label: "Date Only"},
          %{value: "time_only", label: "Time Only"},
          %{value: "filename_safe", label: "Filename Safe"},
          %{value: "custom", label: "Custom"}
        ],
        description: "Timestamp format"
      },
      custom_format: %{
        type: :string,
        label: "CUSTOM FORMAT",
        default: "%Y-%m-%d_%H-%M-%S",
        optional: true,
        description: "Custom strftime format string"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      timestamp: %{
        type: :string,
        label: "TIMESTAMP",
        description: "Formatted timestamp"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    format = inputs["format"] || config["format"] || "iso8601"
    custom_format = inputs["custom_format"] || config["custom_format"] || "%Y-%m-%d_%H-%M-%S"

    timestamp = generate_timestamp(format, custom_format)

    {:ok, %{"timestamp" => timestamp}}
  rescue
    e ->
      Logger.error("DateTimeStamp exception: #{inspect(e)}")
      {:error, "Failed to generate timestamp: #{Exception.message(e)}"}
  end

  defp generate_timestamp(format, custom_format) do
    now = DateTime.utc_now()

    case format do
      "iso8601" ->
        DateTime.to_iso8601(now)

      "date_only" ->
        Date.utc_today() |> Date.to_string()

      "time_only" ->
        Time.utc_now() |> Time.to_string()

      "filename_safe" ->
        # Safe for filenames: 2024-01-17_10-30-45
        Calendar.strftime(now, "%Y-%m-%d_%H-%M-%S")

      "custom" ->
        Calendar.strftime(now, custom_format)

      _ ->
        DateTime.to_iso8601(now)
    end
  end
end
