defmodule LeaxerCore.Nodes.Utility.RegexMatch do
  @moduledoc """
  Tests if a string matches a regular expression pattern.
  """
  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Nodes.Helpers

  @impl true
  def type, do: "RegexMatch"

  @impl true
  def label, do: "Regex Match"

  @impl true
  def category, do: "Text/Regex"

  @impl true
  def description, do: "Tests if text matches a regular expression pattern"

  @impl true
  def input_spec do
    %{
      text: %{type: :string, label: "TEXT", multiline: true, configurable: false},
      pattern: %{
        type: :string,
        label: "PATTERN",
        default: "",
        configurable: true,
        placeholder: "e.g. \\d+",
        description: "Regular expression pattern"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{type: :boolean, label: "RESULT"},
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
        {:ok, %{"result" => false, "error" => nil}}

      {:ok, regex} ->
        {:ok, %{"result" => Regex.match?(regex, text), "error" => nil}}

      {:error, reason} ->
        {:ok, %{"result" => false, "error" => reason}}
    end
  end
end
