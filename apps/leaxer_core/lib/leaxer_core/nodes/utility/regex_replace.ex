defmodule LeaxerCore.Nodes.Utility.RegexReplace do
  @moduledoc """
  Replaces text matching a regular expression with a replacement string.
  """
  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "RegexReplace"

  @impl true
  def label, do: "Regex Replace"

  @impl true
  def category, do: "Text/Regex"

  @impl true
  def description, do: "Replaces regex pattern matches with a replacement string"

  @impl true
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", default: "", multiline: true, configurable: true},
      pattern: %{
        type: :string,
        label: "PATTERN",
        default: "",
        configurable: true,
        placeholder: "e.g. \\d+",
        description: "Regular expression pattern to match"
      },
      replace: %{
        type: :string,
        label: "REPLACE",
        default: "",
        configurable: true,
        placeholder: "Replacement text",
        description: "Text to replace matches with"
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
    replace = Helpers.get_value("replace", inputs, config, "") |> to_string()

    case Helpers.compile_regex(pattern) do
      :empty ->
        {:ok, %{"result" => text, "error" => nil}}

      {:ok, regex} ->
        {:ok, %{"result" => Regex.replace(regex, text, replace), "error" => nil}}

      {:error, reason} ->
        {:ok, %{"result" => text, "error" => reason}}
    end
  end
end
