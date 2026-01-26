defmodule LeaxerCore.Nodes.Dataset.PromptBuilder do
  @moduledoc """
  Combine prefix + main + suffix with separators.

  Reduces graph complexity - 1 node instead of 5 Concat nodes.
  Essential for building complex prompts from components.

  ## Examples

      iex> PromptBuilder.process(%{"prefix" => "masterpiece", "main" => "cat", "suffix" => "8k"}, %{"separator" => "comma"})
      {:ok, %{"prompt" => "masterpiece, cat, 8k"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "PromptBuilder"

  @impl true
  def label, do: "Prompt Builder"

  @impl true
  def category, do: "Data/Prompt"

  @impl true
  def description, do: "Combine prefix + main + suffix with configurable separator"

  @impl true
  def input_spec do
    %{
      prefix: %{
        type: :string,
        label: "PREFIX",
        default: "",
        optional: true,
        description: "Text to prepend"
      },
      main: %{
        type: :string,
        label: "MAIN",
        default: "",
        description: "Main prompt text"
      },
      suffix: %{
        type: :string,
        label: "SUFFIX",
        default: "",
        optional: true,
        description: "Text to append"
      },
      separator: %{
        type: :enum,
        label: "SEPARATOR",
        default: "comma",
        options: [
          %{value: "comma", label: "Comma"},
          %{value: "space", label: "Space"},
          %{value: "newline", label: "Newline"},
          %{value: "none", label: "None"}
        ],
        description: "Separator between parts"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      prompt: %{
        type: :string,
        label: "PROMPT",
        description: "Combined prompt text"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    prefix = inputs["prefix"] || config["prefix"] || ""
    main = inputs["main"] || config["main"] || ""
    suffix = inputs["suffix"] || config["suffix"] || ""
    separator = inputs["separator"] || config["separator"] || "comma"

    parts =
      [prefix, main, suffix]
      |> Enum.reject(&(&1 == ""))

    separator_char =
      case separator do
        "comma" -> ", "
        "space" -> " "
        "newline" -> "\n"
        "none" -> ""
        _ -> ", "
      end

    prompt = Enum.join(parts, separator_char)

    {:ok, %{"prompt" => prompt}}
  rescue
    e ->
      Logger.error("PromptBuilder exception: #{inspect(e)}")
      {:error, "Failed to build prompt: #{Exception.message(e)}"}
  end
end
