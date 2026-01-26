defmodule LeaxerCore.Nodes.Dataset.ListFromText do
  @moduledoc """
  Split text into list by delimiter.

  Essential for converting inline text to list format for use
  with other dataset nodes.

  ## Examples

      iex> ListFromText.process(%{"text" => "a,b,c", "delimiter" => "comma"}, %{})
      {:ok, %{"list" => ["a", "b", "c"]}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "ListFromText"

  @impl true
  def label, do: "List From Text"

  @impl true
  def category, do: "Data/List"

  @impl true
  def description, do: "Split text into list by delimiter"

  @impl true
  def input_spec do
    %{
      text: %{
        type: :string,
        label: "TEXT",
        default: "",
        description: "Text to split into list"
      },
      delimiter: %{
        type: :enum,
        label: "DELIMITER",
        default: "newline",
        options: [
          %{value: "newline", label: "Newline"},
          %{value: "comma", label: "Comma"},
          %{value: "space", label: "Space"},
          %{value: "custom", label: "Custom"}
        ],
        description: "Character to split on"
      },
      custom_delimiter: %{
        type: :string,
        label: "CUSTOM DELIMITER",
        default: "",
        optional: true,
        description: "Custom delimiter (if delimiter is 'custom')"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      list: %{
        type: {:list, :string},
        label: "LIST",
        description: "List of split text items"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    text = inputs["text"] || config["text"] || ""
    delimiter_type = inputs["delimiter"] || config["delimiter"] || "newline"
    custom_delimiter = inputs["custom_delimiter"] || config["custom_delimiter"] || ""

    if text == "" do
      {:ok, %{"list" => []}}
    else
      delimiter =
        case delimiter_type do
          "newline" -> "\n"
          "comma" -> ","
          "space" -> " "
          "custom" -> custom_delimiter
          _ -> "\n"
        end

      list =
        String.split(text, delimiter)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:ok, %{"list" => list}}
    end
  rescue
    e ->
      Logger.error("ListFromText exception: #{inspect(e)}")
      {:error, "Failed to split text: #{Exception.message(e)}"}
  end
end
