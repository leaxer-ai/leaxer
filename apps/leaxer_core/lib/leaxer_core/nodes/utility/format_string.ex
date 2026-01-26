defmodule LeaxerCore.Nodes.Utility.FormatString do
  @moduledoc """
  Template strings with variable substitution.

  Essential for dynamic filenames and prompts with variables.
  Supports simple {variable} syntax.

  ## Examples

      iex> FormatString.process(%{"template" => "Image_{index}_{seed}.png", "index" => 5, "seed" => 12345}, %{})
      {:ok, %{"result" => "Image_5_12345.png"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "FormatString"

  @impl true
  def label, do: "Format String"

  @impl true
  def category, do: "Utility/Format"

  @impl true
  def description, do: "Template strings with variable substitution"

  @impl true
  def input_spec do
    %{
      template: %{
        type: :string,
        label: "TEMPLATE",
        default: "",
        description: "Template string with {variable} placeholders"
      },
      # Additional variables will be added dynamically via inputs
      var1: %{
        type: :string,
        label: "VAR 1",
        default: "",
        optional: true,
        description: "First variable value"
      },
      var2: %{
        type: :string,
        label: "VAR 2",
        default: "",
        optional: true,
        description: "Second variable value"
      },
      var3: %{
        type: :string,
        label: "VAR 3",
        default: "",
        optional: true,
        description: "Third variable value"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{
        type: :string,
        label: "RESULT",
        description: "Formatted string"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    template = inputs["template"] || config["template"] || ""

    if template == "" do
      {:ok, %{"result" => ""}}
    else
      # Merge all inputs and config for variable substitution
      variables = Map.merge(config, inputs)
      result = format_template(template, variables)

      {:ok, %{"result" => result}}
    end
  rescue
    e ->
      Logger.error("FormatString exception: #{inspect(e)}")
      {:error, "Failed to format string: #{Exception.message(e)}"}
  end

  defp format_template(template, variables) do
    # Find all {variable} patterns and replace with values
    pattern = ~r/\{([^}]+)\}/

    Regex.replace(pattern, template, fn _, var_name ->
      # Try to find the variable in inputs
      case Map.get(variables, var_name) do
        # Keep placeholder if not found
        nil -> "{#{var_name}}"
        value when is_binary(value) -> value
        # Convert non-strings
        value -> to_string(value)
      end
    end)
  end
end
