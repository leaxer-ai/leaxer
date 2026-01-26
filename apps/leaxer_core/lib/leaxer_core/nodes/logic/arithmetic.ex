defmodule LeaxerCore.Nodes.Logic.Arithmetic do
  @moduledoc """
  Perform arithmetic operations between two values.

  Ported from isekai-comfy-node's IsekaiArithmetic.
  Supports: +, -, ×, ÷, %, ^ (power)
  Returns both float and int results for logic workflows.

  ## Examples

      iex> Arithmetic.process(%{"a" => 10.0, "operation" => "+", "b" => 5.0}, %{})
      {:ok, %{"result" => 15.0, "int_result" => 15}}
  """

  use LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Helpers
  require Logger

  @impl true
  def type, do: "Arithmetic"

  @impl true
  def label, do: "Arithmetic"

  @impl true
  def category, do: "Logic/Flow"

  @impl true
  def description, do: "Perform arithmetic operations (+, -, ×, ÷, %, ^)"

  @impl true
  def input_spec do
    %{
      a: %{
        type: :float,
        label: "A",
        default: 0.0,
        min: -999_999.0,
        max: 999_999.0,
        step: 0.01
      },
      operation: %{
        type: :enum,
        label: "OPERATION",
        default: "+",
        options: [
          %{value: "+", label: "Add (+)"},
          %{value: "-", label: "Subtract (−)"},
          %{value: "×", label: "Multiply (×)"},
          %{value: "÷", label: "Divide (÷)"},
          %{value: "%", label: "Modulo (%)"},
          %{value: "^", label: "Power (^)"}
        ]
      },
      b: %{
        type: :float,
        label: "B",
        default: 0.0,
        min: -999_999.0,
        max: 999_999.0,
        step: 0.01
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{
        type: :float,
        label: "RESULT"
      },
      int_result: %{
        type: :integer,
        label: "INT RESULT"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    a = Helpers.get_value("a", inputs, config, 0.0)
    operation = Helpers.get_value("operation", inputs, config, "+")
    b = Helpers.get_value("b", inputs, config, 0.0)

    result =
      case operation do
        "+" -> a + b
        "-" -> a - b
        "×" -> a * b
        "÷" -> if b != 0, do: a / b, else: 0.0
        "%" -> if b != 0, do: :math.fmod(a, b), else: 0.0
        "^" -> :math.pow(a, b)
        _ -> 0.0
      end

    int_result = trunc(result)

    Logger.info("Arithmetic: #{a} #{operation} #{b} = #{result}")

    {:ok,
     %{
       "result" => result,
       "int_result" => int_result
     }}
  rescue
    e ->
      Logger.error("Arithmetic exception: #{inspect(e)}")
      {:ok, %{"result" => 0.0, "int_result" => 0}}
  end
end
