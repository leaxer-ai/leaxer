defmodule LeaxerCore.Nodes.Utility.RegexExtract do
  @moduledoc """
  Extracts the first match of a regular expression from a string.
  """
  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "RegexExtract"

  @impl true
  def label, do: "Regex Extract"

  @impl true
  def category, do: "Text/Regex"

  @impl true
  def description, do: "Extracts the first match of a regex pattern from text"

  @impl true
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", multiline: true, configurable: false},
      pattern: %{
        type: :string,
        label: "PATTERN",
        default: "",
        configurable: true,
        placeholder: "e.g. (\\w+)",
        description: "Regular expression pattern (use groups for specific extraction)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{type: :string, label: "RESULT"},
      error: %{type: :string, label: "ERROR"}
    }
  end

  @impl true
  def validate(inputs, config) do
    Helpers.validate_regex("pattern", inputs, config)
  end

  @impl true
  def process(inputs, config) do
    text = Helpers.get_value("text", inputs, config, "") |> to_string()
    pattern = Helpers.get_value("pattern", inputs, config, "") |> to_string()

    case Helpers.compile_regex(pattern) do
      :empty ->
        {:ok, %{"result" => "", "error" => nil}}

      {:ok, regex} ->
        result =
          case Regex.run(regex, text) do
            [match | _] -> match
            nil -> ""
          end

        {:ok, %{"result" => result, "error" => nil}}

      {:error, reason} ->
        {:ok, %{"result" => "", "error" => reason}}
    end
  end
end
