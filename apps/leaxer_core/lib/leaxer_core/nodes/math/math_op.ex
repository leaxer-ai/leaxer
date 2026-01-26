defmodule LeaxerCore.Nodes.Math.MathOp do
  @moduledoc """
  Combined math operation node supporting add, subtract, multiply, divide, modulo, and power.
  """
  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "MathOp"

  @impl true
  def label, do: "Math Operation"

  @impl true
  def category, do: "Math/Arithmetic"

  @impl true
  def description,
    do: "Perform arithmetic operations: add, subtract, multiply, divide, modulo, power"

  @impl true
  def input_spec do
    %{
      a: %{type: :float, label: "A", default: 0.0},
      b: %{type: :float, label: "B", default: 0.0},
      operation: %{
        type: :enum,
        label: "OPERATION",
        default: "add",
        options: [
          %{value: "add", label: "Add (+)"},
          %{value: "subtract", label: "Subtract (-)"},
          %{value: "multiply", label: "Multiply (×)"},
          %{value: "divide", label: "Divide (÷)"},
          %{value: "modulo", label: "Modulo (%)"},
          %{value: "power", label: "Power (^)"}
        ]
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{type: :float, label: "RESULT"}
    }
  end

  @impl true
  def process(inputs, config) do
    a = inputs["a"] || config["a"] || 0.0
    b = inputs["b"] || config["b"] || 0.0
    operation = config["operation"] || "add"

    result =
      case operation do
        "add" -> a + b
        "subtract" -> a - b
        "multiply" -> a * b
        "divide" -> if b == 0, do: 0.0, else: a / b
        "modulo" -> if b == 0, do: 0.0, else: :math.fmod(a, b)
        "power" -> :math.pow(a, b)
        _ -> a + b
      end

    {:ok, %{"result" => result}}
  end
end
