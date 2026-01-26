defmodule LeaxerCore.Nodes.Utility.ConcatenateAdvanced do
  @moduledoc """
  Join multiple string inputs with a configurable delimiter.

  Ported from isekai-comfy-node's IsekaiConcatenateString.
  Accepts up to 10 optional string inputs and concatenates them.
  Only non-empty inputs are included.

  ## Examples

      iex> ConcatenateAdvanced.process(%{"text_a" => "portrait", "text_b" => "of a warrior", "delimiter" => " "}, %{})
      {:ok, %{"result" => "portrait of a warrior"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "ConcatenateAdvanced"

  @impl true
  def label, do: "Concatenate (Advanced)"

  @impl true
  def category, do: "Text/Manipulation"

  @impl true
  def description, do: "Join multiple string inputs with a delimiter (up to 10 inputs)"

  @impl true
  def input_spec do
    %{
      delimiter: %{
        type: :string,
        label: "DELIMITER",
        default: " ",
        description: "String to use between joined texts"
      },
      text_a: %{
        type: :string,
        label: "TEXT A",
        default: "",
        optional: true,
        multiline: true
      },
      text_b: %{
        type: :string,
        label: "TEXT B",
        default: "",
        optional: true,
        multiline: true
      },
      text_c: %{
        type: :string,
        label: "TEXT C",
        default: "",
        optional: true,
        multiline: true
      },
      text_d: %{
        type: :string,
        label: "TEXT D",
        default: "",
        optional: true,
        multiline: true
      },
      text_e: %{
        type: :string,
        label: "TEXT E",
        default: "",
        optional: true,
        multiline: true
      },
      text_f: %{
        type: :string,
        label: "TEXT F",
        default: "",
        optional: true,
        multiline: true
      },
      text_g: %{
        type: :string,
        label: "TEXT G",
        default: "",
        optional: true,
        multiline: true
      },
      text_h: %{
        type: :string,
        label: "TEXT H",
        default: "",
        optional: true,
        multiline: true
      },
      text_i: %{
        type: :string,
        label: "TEXT I",
        default: "",
        optional: true,
        multiline: true
      },
      text_j: %{
        type: :string,
        label: "TEXT J",
        default: "",
        optional: true,
        multiline: true
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{
        type: :string,
        label: "RESULT",
        description: "Concatenated string"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    delimiter = inputs["delimiter"] || config["delimiter"] || " "

    # Collect all text inputs in order
    text_keys = [
      "text_a",
      "text_b",
      "text_c",
      "text_d",
      "text_e",
      "text_f",
      "text_g",
      "text_h",
      "text_i",
      "text_j"
    ]

    valid_texts =
      text_keys
      |> Enum.map(fn key -> inputs[key] || config[key] end)
      |> Enum.reject(&is_nil_or_empty/1)

    result =
      if valid_texts == [] do
        ""
      else
        Enum.join(valid_texts, delimiter)
      end

    Logger.info("ConcatenateAdvanced: Joined #{length(valid_texts)} inputs")

    {:ok, %{"result" => result}}
  rescue
    e ->
      Logger.error("ConcatenateAdvanced exception: #{inspect(e)}")
      {:error, "Failed to concatenate: #{Exception.message(e)}"}
  end

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_), do: false
end
