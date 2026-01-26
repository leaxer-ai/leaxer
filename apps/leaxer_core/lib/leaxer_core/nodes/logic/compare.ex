defmodule LeaxerCore.Nodes.Logic.Compare do
  @moduledoc """
  Comparison node that compares two values using various operators.
  """
  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers

  @impl true
  @spec type() :: String.t()
  def type, do: "Compare"

  @impl true
  @spec label() :: String.t()
  def label, do: "Compare"

  @impl true
  @spec category() :: String.t()
  def category, do: "Logic/Flow"

  @impl true
  @spec description() :: String.t()
  def description,
    do: "Compares two values using a specified operator and returns a boolean result"

  @impl true
  @spec input_spec() :: %{a: map(), b: map(), operator: map()}
  def input_spec do
    %{
      a: %{type: :any, label: "A"},
      b: %{type: :any, label: "B"},
      operator: %{
        type: :enum,
        label: "OPERATOR",
        default: "==",
        options: [
          %{value: "==", label: "Equal (==)"},
          %{value: "!=", label: "Not Equal (!=)"},
          %{value: "<", label: "Less Than (<)"},
          %{value: ">", label: "Greater Than (>)"},
          %{value: "<=", label: "Less or Equal (<=)"},
          %{value: ">=", label: "Greater or Equal (>=)"}
        ]
      }
    }
  end

  @impl true
  @spec output_spec() :: %{result: map(), int_result: map()}
  def output_spec do
    %{
      result: %{type: :boolean, label: "RESULT"},
      int_result: %{type: :integer, label: "INT RESULT", description: "1 for true, 0 for false"}
    }
  end

  @impl true
  @spec process(map(), map()) :: {:ok, %{String.t() => boolean() | integer()}}
  def process(inputs, config) do
    a = Helpers.get_value("a", inputs, config, nil)
    b = Helpers.get_value("b", inputs, config, nil)
    operator = Helpers.get_value("operator", inputs, config, "==")

    result =
      case operator do
        "==" -> a == b
        "!=" -> a != b
        "<" -> compare_lt(a, b)
        ">" -> compare_gt(a, b)
        "<=" -> compare_lte(a, b)
        ">=" -> compare_gte(a, b)
        _ -> a == b
      end

    int_result = if result, do: 1, else: 0

    {:ok, %{"result" => result, "int_result" => int_result}}
  end

  @spec compare_lt(any(), any()) :: boolean()
  defp compare_lt(a, b) when is_number(a) and is_number(b), do: a < b
  defp compare_lt(a, b) when is_binary(a) and is_binary(b), do: a < b
  defp compare_lt(_, _), do: false

  @spec compare_gt(any(), any()) :: boolean()
  defp compare_gt(a, b) when is_number(a) and is_number(b), do: a > b
  defp compare_gt(a, b) when is_binary(a) and is_binary(b), do: a > b
  defp compare_gt(_, _), do: false

  @spec compare_lte(any(), any()) :: boolean()
  defp compare_lte(a, b) when is_number(a) and is_number(b), do: a <= b
  defp compare_lte(a, b) when is_binary(a) and is_binary(b), do: a <= b
  defp compare_lte(_, _), do: false

  @spec compare_gte(any(), any()) :: boolean()
  defp compare_gte(a, b) when is_number(a) and is_number(b), do: a >= b
  defp compare_gte(a, b) when is_binary(a) and is_binary(b), do: a >= b
  defp compare_gte(_, _), do: false
end
